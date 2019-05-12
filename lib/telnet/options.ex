defmodule Telnet.Options do
  @moduledoc """
  Parse telnet IAC options coming from the game
  """

  alias Telnet.GMCP
  alias Telnet.MSSP
  alias Telnet.OAuth

  @se 240
  @nop 241
  @ga 249
  @sb 250
  @will 251
  @wont 252
  @iac_do 253
  @dont 254
  @iac 255

  @echo 1
  @term_type 24
  @line_mode 34
  @new_environ 39
  @charset 42
  @mssp 70
  @oauth 165
  @gmcp 201

  @charset_request 1
  @term_type_send 1

  def mssp_data?(options) do
    Enum.any?(options, fn option ->
      match?({:mssp, _}, option)
    end)
  end

  def text_mssp?(string) do
    string =~ "MSSP-REPLY-START"
  end

  def get_mssp_data(options) do
    Enum.find(options, fn option ->
      match?({:mssp, _}, option)
    end)
  end

  @doc """
  Parse binary data from a MUD into any telnet options found and known
  """
  def parse(binary) do
    {options, leftover} = options(binary, <<>>, [], binary)

    options =
      options
      |> Enum.reject(&(&1 == <<>>))
      |> Enum.map(&transform/1)

    string =
      options
      |> Enum.filter(&is_string?/1)
      |> Enum.map(&(elem(&1, 1)))
      |> Enum.join()

    options =
      options
      |> Enum.reject(&is_unknown_option?/1)
      |> Enum.reject(&is_string?/1)

    {options, string, strip_to_iac(leftover)}
  end

  defp is_unknown_option?(option), do: option == :unknown

  defp is_string?({:string, _}), do: true

  defp is_string?(_), do: false

  defp strip_to_iac(<<>>), do: <<>>

  defp strip_to_iac(<<@iac, data::binary>>), do: <<@iac>> <> data

  defp strip_to_iac(<<_byte::size(8), data::binary>>) do
    strip_to_iac(data)
  end

  @doc """
  Parse options out of a binary stream
  """
  def options(<<>>, current, stack, leftover) do
    {stack ++ [current], leftover}
  end

  def options(<<@iac, @sb, data::binary>>, current, stack, leftover) do
    case parse_sub_negotiation(<<@iac, @sb>> <> data) do
      :error ->
        {stack ++ [current], leftover}

      {sub, data} ->
        options(data, <<>>, stack ++ [current, sub], data)
    end
  end

  def options(<<@iac, @will, byte::size(8), data::binary>>, current, stack, _leftover) do
    options(data, <<>>, stack ++ [current, <<@iac, @will, byte>>], data)
  end

  def options(<<@iac, @wont, byte::size(8), data::binary>>, current, stack, _leftover) do
    options(data, <<>>, stack ++ [current, <<@iac, @wont, byte>>], data)
  end

  def options(<<@iac, @iac_do, byte::size(8), data::binary>>, current, stack, _leftover) do
    options(data, <<>>, stack ++ [current, <<@iac, @iac_do, byte>>], data)
  end

  def options(<<@iac, @dont, byte::size(8), data::binary>>, current, stack, _leftover) do
    options(data, <<>>, stack ++ [current, <<@iac, @dont, byte>>], data)
  end

  def options(<<@iac, @ga, data::binary>>, current, stack, _leftover) do
    options(data, <<>>, stack ++ [current, <<@iac, @ga>>], data)
  end

  def options(<<@iac, @nop, data::binary>>, current, stack, _leftover) do
    options(data, <<>>, stack ++ [current, <<@iac, @nop>>], data)
  end

  def options(<<@iac, data::binary>>, current, stack, leftover) do
    options(data, <<@iac>>, stack ++ [current], leftover)
  end

  def options(<<byte::size(8), data::binary>>, current, stack, leftover) do
    options(data, current <> <<byte>>, stack, leftover)
  end

  @doc """
  Parse sub negotiation options out of a stream
  """
  def parse_sub_negotiation(data, stack \\ <<>>)

  def parse_sub_negotiation(<<>>, _stack), do: :error

  def parse_sub_negotiation(<<byte::size(8), @iac, @se, data::binary>>, stack) do
    {stack <> <<byte, @iac, @se>>, data}
  end

  def parse_sub_negotiation(<<byte::size(8), data::binary>>, stack) do
    parse_sub_negotiation(data, stack <> <<byte>>)
  end

  @doc """
  Transform IAC binary data to actionable terms

      iex> Options.transform(<<255, 251, 1>>)
      {:will, :echo}

      iex> Options.transform(<<255, 252, 1>>)
      {:wont, :echo}

      iex> Options.transform(<<255, 253, 1>>)
      {:do, :echo}

      iex> Options.transform(<<255, 254, 1>>)
      {:dont, :echo}

  Returns a generic DO/WILL if the specific term is not known. For
  responding with the opposite command to reject.

      iex> Options.transform(<<255, 251, 2>>)
      {:will, 2}

      iex> Options.transform(<<255, 252, 2>>)
      {:wont, 2}

      iex> Options.transform(<<255, 253, 2>>)
      {:do, 2}

      iex> Options.transform(<<255, 254, 2>>)
      {:dont, 2}

  Everything else is parsed as `:unknown`

      iex> Options.transform(<<255>>)
      :unknown
  """
  def transform(<<@iac, @will, byte>>), do: {:will, byte_to_option(byte)}

  def transform(<<@iac, @wont, byte>>), do: {:wont, byte_to_option(byte)}

  def transform(<<@iac, @iac_do, byte>>), do: {:do, byte_to_option(byte)}

  def transform(<<@iac, @dont, byte>>), do: {:dont, byte_to_option(byte)}

  def transform(<<@iac, @sb, @mssp, data::binary>>) do
    case MSSP.parse(<<@iac, @sb, @mssp, data::binary>>) do
      :error ->
        :unknown

      {:ok, data} ->
        {:mssp, data}
    end
  end

  def transform(<<@iac, @sb, @term_type, @term_type_send, @iac, @se>>) do
    {:send, :term_type}
  end

  def transform(<<@iac, @sb, @charset, @charset_request, sep::size(8), data::binary>>) do
    data = parse_charset(data)
    {:charset, :request, <<sep>>, data}
  end

  def transform(<<@iac, @sb, @oauth, data::binary>>) do
    case OAuth.parse(data) do
      {:ok, module, data} ->
        {:oauth, module, data}

      :error ->
        :unknown
    end
  end

  def transform(<<@iac, @sb, @gmcp, data::binary>>) do
    case GMCP.parse(data) do
      {:ok, module, data} ->
        {:gmcp, module, data}

      :error ->
        :unknown
    end
  end

  def transform(<<@iac, @sb, _data::binary>>) do
    :unknown
  end

  def transform(<<@iac, @ga>>), do: {:ga}

  def transform(<<@iac, @nop>>), do: {:nop}

  def transform(<<@iac, _byte::size(8)>>), do: :unknown

  def transform(<<@iac>>), do: :unknown

  def transform(binary), do: {:string, binary}

  @doc """
  Strip the final IAC SE from the charset
  """
  def parse_charset(<<@iac, @se>>) do
    <<>>
  end

  def parse_charset(<<byte::size(8), data::binary>>) do
    <<byte>> <> parse_charset(data)
  end

  @doc """
  Convert a byte to a known option, or leave as as the byte

      iex> Options.byte_to_option(1)
      :echo

      iex> Options.byte_to_option(24)
      :term_type

      iex> Options.byte_to_option(34)
      :line_mode

      iex> Options.byte_to_option(39)
      :new_environ

      iex> Options.byte_to_option(42)
      :charset

      iex> Options.byte_to_option(70)
      :mssp

      iex> Options.byte_to_option(165)
      :oauth

      iex> Options.byte_to_option(201)
      :gmcp
  """
  def byte_to_option(@echo), do: :echo

  def byte_to_option(@term_type), do: :term_type

  def byte_to_option(@line_mode), do: :line_mode

  def byte_to_option(@new_environ), do: :new_environ

  def byte_to_option(@charset), do: :charset

  def byte_to_option(@mssp), do: :mssp

  def byte_to_option(@oauth), do: :oauth

  def byte_to_option(@gmcp), do: :gmcp

  def byte_to_option(byte), do: byte

  @doc """
  Convert a known option back to a byte or pass through the byte

      iex> Options.option_to_byte(:echo)
      1

      iex> Options.option_to_byte(:term_type)
      24

      iex> Options.option_to_byte(:line_mode)
      34

      iex> Options.option_to_byte(:new_environ)
      39

      iex> Options.option_to_byte(:charset)
      42

      iex> Options.option_to_byte(:mssp)
      70

      iex> Options.option_to_byte(:oauth)
      165

      iex> Options.option_to_byte(:gmcp)
      201
  """
  def option_to_byte(:echo), do: @echo

  def option_to_byte(:term_type), do: @term_type

  def option_to_byte(:line_mode), do: @line_mode

  def option_to_byte(:new_environ), do: @new_environ

  def option_to_byte(:charset), do: @charset

  def option_to_byte(:mssp), do: @mssp

  def option_to_byte(:oauth), do: @oauth

  def option_to_byte(:gmcp), do: @gmcp

  def option_to_byte(byte), do: byte
end
