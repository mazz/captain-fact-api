defmodule CF.GraphQL.Schema.Types.User do
  @moduledoc """
  Representation of a `DB.Schema.User` for Absinthe
  """

  use Absinthe.Schema.Notation
  use Absinthe.Ecto, repo: DB.Repo

  import CF.Graphql.Schema.Utils
  alias CF.GraphQL.Resolvers

  import_types(CF.GraphQL.Schema.Types.Paginated)

  @desc "A user registered on the website"
  object :user do
    @desc "Unique user ID"
    field(:id, non_null(:id))
    @desc "Unique username"
    field(:username, non_null(:string))
    @desc "Optional full-name"
    field(:name, :string)
    @desc "Reputation of the user. See https://captainfact.io/help/reputation"
    field(:reputation, :integer)
    @desc "User picture url (96x96)"
    field(:picture_url, non_null(:string), do: resolve(&Resolvers.Users.picture_url/3))
    @desc "Small version of the user picture (48x48)"
    field(:mini_picture_url, non_null(:string), do: resolve(&Resolvers.Users.mini_picture_url/3))
    @desc "A list of user's achievements as a list of integers"
    field(:achievements, list_of(:integer))
    @desc "User's registration datetime"
    field(:registered_at, :string, do: fn u, _, _ -> {:ok, u.inserted_at} end)
    @desc "User activity log"
    field :actions, :activity_log do
      complexity(join_complexity())
      arg(:offset, :integer, default_value: 1)
      arg(:limit, :integer, default_value: 10)
      resolve(&Resolvers.Users.activity_log/3)
    end
  end

  @desc "A paginated list of user actions"
  object :activity_log do
    import_fields(:paginated)
    field(:entries, list_of(:user_action))
  end
end
