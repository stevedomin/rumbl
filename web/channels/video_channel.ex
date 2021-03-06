defmodule Rumbl.VideoChannel do
  use Rumbl.Web, :channel
  alias Rumbl.AnnotationView

  def join("videos:" <> video_id, _params, socket) do
    video = Repo.get!(Rumbl.Video, video_id)
    annotations = Repo.all(
      from a in assoc(video, :annotations),
      order_by: [desc: a.at],
      limit: 200,
      preload: [:user]
    )

    resp = %{annotations: Phoenix.View.render_many(annotations, AnnotationView, "annotation.json")}

    {:ok, resp, assign(socket, :video_id, video.id)}
  end

  def handle_in("new_annotation", params, socket) do
    user = socket.assigns.current_user

    changeset =
      user
      |> build(:annotations, video_id: socket.assigns.video_id)
      |> Rumbl.Annotation.changeset(params)

    case Repo.insert(changeset) do
      {:ok, annotation} ->
        broadcast_annotation(socket, annotation)
        Task.start_link(fn -> compute_additional_info(annotation, socket) end)
        {:reply, :ok, socket}
      {:error, changeset} ->
        {:reply, {:error, %{errors: changeset}}, socket}
    end
  end

  defp broadcast_annotation(socket, annotation) do
    annotation = Repo.preload(annotation, :user)
    rendered_ann = Phoenix.View.render(AnnotationView, "annotation.json", %{
      annotation: annotation
    })
    broadcast! socket, "new_annotation", rendered_ann
  end

  defp compute_additional_info(ann, socket) do
    for result <- Rumbl.InfoSys.compute(ann.body, limit: 1) do
      attrs = %{url: result.url, body: result.text, at: ann.at}
      info_changeset =
        result.backend
        |> build(:annotations, video_id: socket.assigns.video_id)
        |> Rumbl.Annotation.changeset(attrs)

      case Repo.insert(info_changeset) do
        {:ok, info_ann} -> broadcast_annotation(socket, info_ann)
        {:error, _changeset} -> :ignore
      end
    end
  end
end
