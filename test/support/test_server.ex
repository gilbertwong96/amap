defmodule Amap.TestServer do
  @moduledoc false

  # A minimal HTTP/1.1 server for tests, serving canned responses from an
  # ephemeral port.
  #
  # This exists to keep `plug_cowboy`, `cowboy` and `cowlib` out of the
  # dependency tree. Bypass does the same job but arrives with all three, plus
  # `plug` and `ranch`; `:gen_tcp` from OTP covers everything the suite needs.
  #
  # Two semantics are deliberate, because tests depend on them:
  #
  #   * `expect_once/4` arms a route for exactly one request and *replaces* any
  #     previous expectation for that route rather than queueing behind it. A
  #     `for` loop around it therefore leaves one handler armed, not two.
  #   * An unarmed route answers 404, which callers see as
  #     `:unexpected_response` -- how a test notices a request it did not want.
  #
  # Handlers receive a `Request` and return `{status, body}`.
  #
  # An `expect_once/4` that never receives a request fails the test, as Bypass
  # does: a test that armed a response and then never made the call would
  # otherwise pass while asserting nothing. That count lives in a `:counters`
  # ref rather than in this process, because ExUnit stops supervised children
  # *before* running `on_exit` callbacks -- state held in the server is already
  # gone by the time it could be checked.

  use GenServer

  defstruct [:pid, :port, :unconsumed]

  @idle_timeout 30_000
  @reason_phrases %{
    200 => "OK",
    201 => "Created",
    204 => "No Content",
    400 => "Bad Request",
    404 => "Not Found",
    429 => "Too Many Requests",
    500 => "Internal Server Error",
    502 => "Bad Gateway",
    503 => "Service Unavailable",
    504 => "Gateway Timeout"
  }

  defmodule Request do
    @moduledoc false
    @enforce_keys [:method, :path, :query, :headers, :body]
    defstruct [:method, :path, :query, :headers, :body]
  end

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [])

  @doc "Starts a server on an ephemeral port, cleaned up when the test ends."
  def start! do
    child_spec = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]},
      restart: :temporary
    }

    pid = ExUnit.Callbacks.start_supervised!(child_spec)
    unconsumed = :counters.new(1, [])
    server = %__MODULE__{pid: pid, port: GenServer.call(pid, :port), unconsumed: unconsumed}

    ExUnit.Callbacks.on_exit(fn -> verify!(server) end)

    server
  end

  @doc "Arms a route for one request, replacing any expectation already there."
  def expect_once(%__MODULE__{pid: pid, unconsumed: unconsumed}, method, path, handler) do
    :counters.add(unconsumed, 1, 1)
    GenServer.call(pid, {:arm, method, path, handler, {:once, unconsumed}})
  end

  @doc "Arms a route that keeps answering every request."
  def expect(%__MODULE__{pid: pid}, method, path, handler),
    do: GenServer.call(pid, {:arm, method, path, handler, :always})

  @doc "Closes open connections, so further requests are refused."
  def down(%__MODULE__{pid: pid}), do: GenServer.call(pid, :down)

  @doc "Raises if any `expect_once/4` expectation went unused."
  def verify!(%__MODULE__{unconsumed: unconsumed}) do
    case :counters.get(unconsumed, 1) do
      0 ->
        :ok

      count ->
        raise ExUnit.AssertionError,
          message: "#{count} armed expectation(s) never received a request"
    end
  end

  @impl true
  def init(_opts) do
    {:ok, listen} =
      :gen_tcp.listen(0, [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        ip: {127, 0, 0, 1}
      ])

    {:ok, port} = :inet.port(listen)
    owner = self()
    acceptor = spawn_link(fn -> accept(listen, owner) end)

    {:ok, %{listen: listen, port: port, acceptor: acceptor, routes: %{}, connections: %{}}}
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  def handle_call(:down, _from, state) do
    :gen_tcp.close(state.listen)
    Enum.each(state.connections, fn {pid, _ref} -> Process.exit(pid, :kill) end)

    {:reply, :ok, %{state | listen: nil, connections: %{}}}
  end

  def handle_call({:arm, method, path, handler, mode}, _from, state) do
    key = {method, path}

    # Replacing an armed single-shot expectation means that one will never be
    # consumed, so stop counting it against the test.
    case Map.get(state.routes, key) do
      {:once, _handler, ref} when ref != nil -> :counters.sub(ref, 1, 1)
      _absent_or_persistent -> :ok
    end

    entry =
      case mode do
        :always -> {:always, handler, nil}
        {:once, ref} -> {:once, handler, ref}
      end

    {:reply, :ok, %{state | routes: Map.put(state.routes, key, entry)}}
  end

  def handle_call({:route, method, path}, _from, state) do
    key = {method, path}

    case Map.get(state.routes, key) do
      nil ->
        {:reply, :not_found, state}

      {:once, handler, ref} ->
        :counters.sub(ref, 1, 1)
        {:reply, {:ok, handler}, %{state | routes: Map.delete(state.routes, key)}}

      {:always, handler, _ref} ->
        {:reply, {:ok, handler}, state}
    end
  end

  @impl true
  def handle_cast({:connection, pid}, state) do
    ref = Process.monitor(pid)
    {:noreply, %{state | connections: Map.put(state.connections, pid, ref)}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | connections: Map.delete(state.connections, pid)}}
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.connections, fn {pid, _ref} -> Process.exit(pid, :kill) end)
    :ok
  end

  defp accept(listen, owner) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        # Unlinked, so that `down/1` can kill a connection without the kill
        # propagating back through the acceptor and taking the server with it.
        pid = spawn(fn -> await_socket(owner) end)
        GenServer.cast(owner, {:connection, pid})
        :ok = :gen_tcp.controlling_process(socket, pid)
        send(pid, {:socket, socket})
        accept(listen, owner)

      # The listener was closed, by `down/1` or by the server stopping.
      {:error, _reason} ->
        :ok
    end
  end

  defp await_socket(owner) do
    receive do
      {:socket, socket} -> serve(socket, owner, "")
    end
  end

  # Connections stay open for further requests, as a real HTTP/1.1 server does,
  # so client connection pools are not left holding a socket this side closed.
  defp serve(socket, owner, buffer) do
    case read_request(socket, buffer) do
      {:ok, request, rest} ->
        respond(socket, owner, request)
        serve(socket, owner, rest)

      :error ->
        :gen_tcp.close(socket)
    end
  end

  defp respond(socket, owner, request) do
    case GenServer.call(owner, {:route, request.method, request.path}, 5_000) do
      :not_found ->
        send_response(socket, 404, "not found")

      {:ok, handler} ->
        case handler.(request) do
          {status, body} -> send_response(socket, status, body)
          :close -> :gen_tcp.close(socket)
        end
    end
  end

  defp send_response(socket, status, body) do
    reason = Map.get(@reason_phrases, status, "Unknown")

    :gen_tcp.send(socket, [
      "HTTP/1.1 #{status} #{reason}\r\n",
      "content-length: #{byte_size(body)}\r\n",
      "content-type: application/json\r\n",
      "\r\n",
      body
    ])
  end

  defp read_request(socket, buffer) do
    case :binary.match(buffer, "\r\n\r\n") do
      {position, _length} ->
        <<head::binary-size(^position), _::binary-size(4), rest::binary>> = buffer

        with [request_line | header_lines] <- String.split(head, "\r\n"),
             [method, target, _version] <- String.split(request_line, " ", parts: 3) do
          headers = parse_headers(header_lines)
          {path, query} = split_target(target)

          case read_body(socket, rest, content_length(headers)) do
            {:ok, body, remaining} ->
              request = %Request{
                method: method,
                path: path,
                query: query,
                headers: headers,
                body: body
              }

              {:ok, request, remaining}

            :error ->
              :error
          end
        else
          _malformed -> :error
        end

      :nomatch ->
        case :gen_tcp.recv(socket, 0, @idle_timeout) do
          {:ok, data} -> read_request(socket, buffer <> data)
          {:error, _reason} -> :error
        end
    end
  end

  defp read_body(_socket, rest, length) when byte_size(rest) >= length do
    <<body::binary-size(^length), remaining::binary>> = rest
    {:ok, body, remaining}
  end

  defp read_body(socket, rest, length) do
    case :gen_tcp.recv(socket, 0, @idle_timeout) do
      {:ok, data} -> read_body(socket, rest <> data, length)
      {:error, _reason} -> :error
    end
  end

  defp content_length(headers) do
    case Integer.parse(Map.get(headers, "content-length", "0")) do
      {length, _rest} when length >= 0 -> length
      _invalid -> 0
    end
  end

  defp parse_headers(lines) do
    Enum.reduce(lines, %{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [name, value] -> Map.put(acc, String.downcase(name), String.trim(value))
        _malformed -> acc
      end
    end)
  end

  defp split_target(target) do
    case String.split(target, "?", parts: 2) do
      [path] -> {path, ""}
      [path, query] -> {path, query}
    end
  end
end
