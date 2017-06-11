Code.require_file("seed_with_csv.exs", __DIR__)
require Arc.Ecto.Schema

alias CaptainFact.Repo
alias CaptainFact.Speaker
alias CaptainFact.SpeakerPicture


defmodule SeedPoliticians do
  @columns_mapping %{
    "image" => :picture,
    "politicianLabel" => :full_name,
    "politician" => :wiki_url
  }
  @title_separators [",", " and ", ".", "&"]

  def seed(fetch_pictures?) do
    csv_path = __DIR__ <> "/data/french_politicians.csv"
    if fetch_pictures? do
      SeedWithCSV.seed(csv_path, @columns_mapping, &seed_politician_with_picture/1)
    else
      SeedWithCSV.seed(csv_path, @columns_mapping, &seed_politician/1)
    end
  end

  defp seed_politician_with_picture(changes) do
    {picture_url, changes} = Map.pop(changes, :picture)
    with speaker when not is_nil(speaker) <- seed_politician(changes),
      do: fetch_picture(speaker, picture_url)
  end

  defp seed_politician(changes) do
    changes =
      changes
      |> Map.delete(:picture)
      |> Map.put(:title, "French Politician")

    changeset =
      %Speaker{is_user_defined: false, country: "FR"}
      |> Speaker.changeset(changes)
    if !changeset.valid? do
      IO.puts(:stderr, "Cannot add speaker #{changes.full_name}: #{inspect(changeset.errors)}")
      nil
    else
      Repo.insert!(changeset)
    end
  end

  defp fetch_picture(speaker, picture_url) do
    {:ok, picture} = SpeakerPicture.store({picture_url, speaker})
    speaker
    |> Ecto.Changeset.change(picture: %{file_name: picture, updated_at: Ecto.DateTime.utc})
    |> Repo.update!()
  end

  def format_title(title) do
    if String.length(title) <= 60 || !String.contains?(title, @title_separators) do
      title
    else
      title
      |> String.reverse()
      |> String.split(Enum.map(@title_separators, &String.reverse/1), parts: 2, trim: true)
      |> List.last()
      |> String.reverse()
      |> String.trim()
      |> format_title()
    end
  end
end

SeedPoliticians.seed(false)