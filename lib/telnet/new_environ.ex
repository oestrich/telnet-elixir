defmodule Telnet.NewEnviron do
  @moduledoc """
  Parse NEW-ENVIRON requests and responses
  """

  @se 240
  @sb 250
  @iac 255

  @new_environ 39

  @is 0
  @send 1

  @var 0
  @value 1
  @uservar 3

  @doc """
  Parse the binary data into Elixir terms

      iex> NewEnviron.parse(<<255, 250, 39, 1, 0>> <> "IPADDRESS" <> <<3>> <> "OTHER" <> <<255, 240>>)
      {:send, ["IPADDRESS", "OTHER"]}

      iex> NewEnviron.parse(<<255, 250, 39, 0, 0>> <> "IPADDRESS" <> <<1>> <> "localhost" <> <<255, 240>>)
      {:is, [{"IPADDRESS", "localhost"}]}
  """
  def parse(<<@iac, @sb, @new_environ, @send, data :: binary>>) do
    data =
      data
      |> strip()
      |> parse_send()

    {:send, data}
  end

  def parse(<<@iac, @sb, @new_environ, @is, data :: binary>>) do
    data =
      data
      |> strip()
      |> parse_is()

    {:is, data}
  end

  @doc """
  Encode a list of variables to request from the server

      iex> NewEnviron.encode(:send, ["IPADDRESS"])
      <<255, 250, 39, 1, 0>> <> "IPADDRESS" <> <<255, 240>>

      iex> NewEnviron.encode(:is, [{"IPADDRESS", "localhost"}])
      <<255, 250, 39, 0, 0>> <> "IPADDRESS" <> <<1>> <> "localhost" <> <<255, 240>>
  """
  def encode(direction, data)

  def encode(:send, variables) do
    data =
      Enum.reduce(variables, <<>>, fn variable, data ->
        data <> <<0>> <> variable
      end)

    <<@iac, @sb, @new_environ, @send>> <> data <> <<@iac, @se>>
  end

  def encode(:is, variables) do
    data =
      Enum.reduce(variables, <<>>, fn {variable, value}, data ->
        data <> <<0>> <> variable <> <<1>> <> value
      end)

    <<@iac, @sb, @new_environ, @is>> <> data <> <<@iac, @se>>
  end

  @doc """
  Strip the final IAC SE
  """
  def strip(<<>>), do: <<>>

  def strip(<<@iac, @se>>), do: <<>>

  def strip(<<byte::size(8), data::binary>>) do
    <<byte>> <> strip(data)
  end

  @doc """
  Parse a SEND packet

      iex> NewEnviron.parse_send(<<0>> <> "IPADDRESS" <> <<3>> <> "OTHER")
      ["IPADDRESS", "OTHER"]

      iex> NewEnviron.parse_send(<<3>> <> "IPADDRESS" <> <<0>> <> "OTHER")
      ["IPADDRESS", "OTHER"]

      iex> NewEnviron.parse_send(<<0>>)
      []
  """
  def parse_send(data) do
    data
    |> parse_is()
    |> Enum.map(fn {key, _val} ->
      key
    end)
  end

  @doc """
  Parse a IS packet

      iex> NewEnviron.parse_is(<<0>> <> "IPADDRESS" <> <<1>> <> "localhost")
      [{"IPADDRESS", "localhost"}]

      iex> NewEnviron.parse_is(<<0>> <> "IPADDRESS" <> <<3>> <> "OTHER")
      [{"IPADDRESS", ""}, {"OTHER", ""}]
  """
  def parse_is(data, buffer_type \\ :var, buffer_var \\ "", buffer_val \\ "", stack \\ [])

  def parse_is(<<>>, _buffer_type, buffer_var, buffer_val, stack) do
    [{buffer_var, buffer_val} | stack]
    |> Enum.reverse()
    |> Enum.reject(& &1 == {"", ""})
  end

  def parse_is(<<@var, data :: binary>>, _buffer_type, buffer_var, buffer_val, stack) do
    parse_is(data, :var, "", "", [{buffer_var, buffer_val} | stack])
  end

  def parse_is(<<@uservar, data :: binary>>, _buffer_type, buffer_var, buffer_val, stack) do
    parse_is(data, :var, "", "", [{buffer_var, buffer_val} | stack])
  end

  def parse_is(<<@value, data :: binary>>, _buffer_type, buffer_var, _buffer_val, stack) do
    parse_is(data, :val, buffer_var, "", stack)
  end

  def parse_is(<<byte :: size(8), data :: binary>>, :var, buffer_var, buffer_val, stack) do
    parse_is(data, :var, buffer_var <> <<byte>>, buffer_val, stack)
  end

  def parse_is(<<byte :: size(8), data :: binary>>, :val, buffer_var, buffer_val, stack) do
    parse_is(data, :val, buffer_var, buffer_val <> <<byte>>, stack)
  end
end
