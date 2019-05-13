defmodule Telnet.NewEnviron do
  @moduledoc """
  Parse NEW-ENVIRON requests and responses
  """

  @doc """
  Parse the binary data into Elixir terms

      iex> NewEnviron.parse(<<255, 250, 39, 1, 0>> <> "IPADDRESS" <> <<0>> <> "OTHER" <> <<255, 240>>)
      {:send, ["IPADDRESS", "OTHER"]}
  """
  def parse(data) do
  end
end
