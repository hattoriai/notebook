defmodule NotebookWeb.MCP.ConsentTest do
  use ExUnit.Case, async: true

  alias NotebookWeb.MCP.Consent

  defp assigns(overrides \\ %{}) do
    Map.merge(
      %{
        flow: :authorization_code,
        client_name: "Claude Code",
        client_host: nil,
        redirect_host: "127.0.0.1:9911",
        loopback?: true,
        subject_display: "Hattori Hanzo",
        scopes: [],
        resource: "https://notebook.example.com/mcp",
        request: "signed-request",
        action: "/oauth/authorize",
        csrf_token: "csrf",
        issuer_name: "notebook.example.com"
      },
      overrides
    )
  end

  defp doc(iodata), do: iodata |> IO.iodata_to_binary() |> LazyHTML.from_document()
  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  test "the consent page asks for the client, for the person, and posts the decision" do
    doc = doc(Consent.render(assigns()))

    assert count(doc, "#consent") == 1
    assert count(doc, "#consent-form input[name=request][value=signed-request]") == 1
    assert count(doc, "#consent-form input[name=_csrf_token][value=csrf]") == 1
    assert count(doc, "#consent-form button[name=decision][value=approve]") == 1
    assert count(doc, "#consent-form button[name=decision][value=deny]") == 1
    # The person is signed in: no Register or Log in in the bar.
    assert count(doc, ".auth-topbar a[href='/users/log-in']") == 0
    assert doc |> LazyHTML.query("#consent-title") |> LazyHTML.text() =~ "Allow Claude Code?"
  end

  test "the error page says what went wrong" do
    doc =
      doc(
        Consent.render_error(%{
          title: "Not allowed",
          message: "That client is unknown.",
          status: 400
        })
      )

    assert count(doc, "#consent-error") == 1
    assert doc |> LazyHTML.query("#consent-error") |> LazyHTML.text() =~ "That client is unknown."
  end
end
