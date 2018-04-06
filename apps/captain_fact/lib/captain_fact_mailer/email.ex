defmodule CaptainFactMailer.Email do
  @moduledoc"""
  Generate emails using templates in `templates` folder. All files must have two
  versions: `.html.eex` and `.text.eex`.

  Templates **must** have an english version (ex: `welcome.en.html.eex`).

  Ideally all templates should also be available in all languages
  specified by @supported_locales.
  """

  use Bamboo.Phoenix, view: CaptainFactMailer.View
  import CaptainFact.Gettext

  require CaptainFactJobs.Reputation

  alias DB.Schema.ResetPasswordRequest
  alias DB.Schema.InvitationRequest
  alias DB.Schema.User

  alias CaptainFactJobs.Reputation


  @sender_no_reply {"CaptainFact", "no-reply@captainfact.io"}
  @supported_locales ~w(fr en)


  @doc"""
  Generate a welcome email to user, with a link to confirm his email address.
  """
  def welcome(user) do
    user_email(user)
    |> subject(gettext_mail_user(user, "Welcome to CaptainFact.io!"))
    |> assign(:confirm_email_reputation, Reputation.self_reputation_change(:email_confirmed))
    |> render_i18n(:welcome)
  end

  @doc"""
  Generate a newsletter email to user with a button to unsubscribe. If user is
  already unsubscribed, return nil.

  [Library] A HTML to Markdown converter would help to generate text_content
  """
  def newsletter(%{newsletter: false}, _, _), do: nil
  def newsletter(user, subject, html_message) do
    user_email(user)
    |> subject(subject)
    |> assign(:content, html_message)
    |> assign(:text_content, Floki.text(html_message))
    |> render_i18n(:newsletter)
  end

  @doc"""
  Generate a reset password email from a ResetPasswordRequest
  """
  def reset_password_request(%ResetPasswordRequest{user: user, token: token, source_ip: ip}) do
    user_email(user)
    |> subject(gettext_mail_user(user, "CaptainFact.io - Reset your password"))
    |> assign(:reset_password_token, token)
    |> assign(:source_ip, ip)
    |> render_i18n(:reset_password)
  end

  @doc"""
  Generate an email for when users fall under a certain reputation threshold
  with the community guidelines.
  """
  def reputation_loss(user) do
    user_email(user)
    |> subject(gettext_mail_user(user, "About your recent loss of reputation on CaptainFact"))
    |> render_i18n(:reputation_loss)
  end

  # No localization for now, we need to store locale in invitation request
  def invitation_to_register(%InvitationRequest{invited_by: invited_by, email: email, token: token}) do
    base_email()
    |> to(email)
    |> subject(invitation_subject(invited_by))
    |> assign(:invitation_token, token)
    |> assign(:invited_by, invited_by)
    |> render_i18n(:invitation)
  end

  defp invitation_subject(nil),
    do: gettext_mail("Your invitation to try CaptainFact.io is ready!")
  defp invitation_subject(user = %User{}),
    do: gettext_mail_user(user, "%{name} invited you to try CaptainFact.io!", name: User.user_appelation(user))

  # Build a base email with `from` set and default layout
  defp base_email() do
    new_email(from: @sender_no_reply)
    |> put_html_layout({CaptainFactMailer.View, "_layout.html"})
    |> put_text_layout({CaptainFactMailer.View, "_layout.text"})
  end

  # Build a base email with user assigned to @user and `to` address set
  defp user_email(user) do
    base_email()
    |> to(user)
    |> assign(:user, user)
  end

  # If a user is available use his locale for rendering email. Otherwise just
  # render with default locale
  defp render_i18n(email = %{assigns: %{user: %{locale: locale}}}, view)
  when locale in @supported_locales
  do
    Gettext.with_locale CaptainFact.Gettext, locale, fn ->
      try do
        render(email, String.to_atom(Atom.to_string(view) <> ".#{locale}"))
      rescue
        # Ideally templates should allways include all versions specified in
        # @supported_locales. But to avoid crashing if not the case, we render
        # the default english template if not found.
        _ in Phoenix.Template.UndefinedError ->
          render(email, String.to_atom(Atom.to_string(view) <> ".en"))
      end
    end
  end
  defp render_i18n(email, view) do
    render(email, String.to_atom(Atom.to_string(view) <> ".en"))
  end
end