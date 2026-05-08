defmodule FieldScribeWeb.FieldScribeLive do
  use FieldScribeWeb, :live_view

  alias FieldScribe.{Projects, Reports}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(FieldScribe.PubSub, Reports.feed_topic())
    end

    initial_project = Projects.list() |> List.first()
    initial_project_id = if initial_project, do: initial_project.id, else: nil

    socket =
      socket
      |> assign(:projects, Projects.list())
      |> assign(:project_id, initial_project_id)
      |> assign(:supervisor, supervisor_default(initial_project_id))
      |> assign(:supervisors, Projects.supervisors_for(initial_project_id || ""))
      |> assign(:report_type, "daily_progress")
      |> assign(:explainer_tab, "elixir")
      |> assign(:active_stage, nil)
      |> assign(:recent_user_submissions, [])
      |> stream(:reports, Reports.list_recent(25))

    {:ok, socket}
  end

  @impl true
  def handle_event("project_changed", %{"project_id" => pid}, socket) do
    {:noreply,
     socket
     |> assign(:project_id, pid)
     |> assign(:supervisors, Projects.supervisors_for(pid))
     |> assign(:supervisor, supervisor_default(pid))}
  end

  def handle_event("supervisor_changed", %{"supervisor" => name}, socket) do
    {:noreply, assign(socket, :supervisor, name)}
  end

  def handle_event("report_type_changed", %{"report_type" => t}, socket)
      when t in ["daily_progress", "issue_blocker"] do
    {:noreply, assign(socket, :report_type, t)}
  end

  def handle_event("explainer_tab", %{"tab" => tab}, socket)
      when tab in ~w(elixir openai apps_script) do
    {:noreply, assign(socket, :explainer_tab, tab)}
  end

  # Fired by the recorder hook after a successful POST to /api/reports.
  # We optimistically prepend a placeholder so the card shows up before
  # the first PubSub broadcast lands.
  def handle_event("report_started", %{"id" => id}, socket) do
    case Reports.get(id) do
      nil ->
        {:noreply, socket}

      report ->
        {:noreply,
         socket
         |> stream_insert(:reports, report, at: 0)
         |> assign(:active_stage, "elixir")
         |> upsert_recent(report)}
    end
  end

  # Fired by the recent_submissions hook on mount: localStorage IDs from
  # this device. We hydrate them with server-side rows so the panel can
  # show transcript previews and Drive links.
  def handle_event("hydrate_recent", %{"ids" => ids}, socket) when is_list(ids) do
    rows = Reports.list_by_ids(ids)
    {:noreply, assign(socket, :recent_user_submissions, rows)}
  end

  def handle_event("hydrate_recent", _params, socket), do: {:noreply, socket}

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:report_status, report}, socket) do
    {:noreply,
     socket
     |> stream_insert(:reports, report, at: 0)
     |> assign(:active_stage, stage_for_status(report.status))
     |> refresh_recent(report)}
  end

  defp supervisor_default(project_id) do
    case Projects.supervisors_for(project_id || "") do
      [first | _] -> first
      _ -> ""
    end
  end

  defp stage_for_status("transcribing"), do: "openai"
  defp stage_for_status("extracting"), do: "openai"
  defp stage_for_status("writing"), do: "apps_script"
  defp stage_for_status("persisted"), do: "apps_script"
  defp stage_for_status("complete"), do: nil
  defp stage_for_status(_), do: "elixir"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="page" id="fs-page" phx-hook="RecentSubmissions">
      <header class="page__header">
        <div class="page__header-inner">
          <h1>Field Scribe</h1>
          <p class="page__tagline">Transform voice notes into structured reports for landscape construction.</p>
        </div>
      </header>

      <main class="page__main">
        <section class="panel panel--form">
          <h2>New report</h2>

          <form id="fs-form" phx-hook="Recorder" phx-change="noop" phx-submit="noop">
            <label>
              <span>Project</span>
              <select
                name="project_id"
                value={@project_id}
                phx-change="project_changed"
              >
                <%= for p <- @projects do %>
                  <option value={p.id} selected={p.id == @project_id}>{p.name}</option>
                <% end %>
              </select>
            </label>

            <label>
              <span>Supervisor</span>
              <select
                name="supervisor"
                value={@supervisor}
                phx-change="supervisor_changed"
              >
                <%= for s <- @supervisors do %>
                  <option value={s} selected={s == @supervisor}>{s}</option>
                <% end %>
              </select>
            </label>

            <label>
              <span>Report type</span>
              <select name="report_type" phx-change="report_type_changed">
                <option value="daily_progress" selected={@report_type == "daily_progress"}>Daily progress</option>
                <option value="issue_blocker" selected={@report_type == "issue_blocker"}>Issue / blocker</option>
              </select>
            </label>

            <div class="record-tips">
              <p class="record-tips__heading">
                {if @report_type == "daily_progress", do: "Cover in your daily progress note:", else: "Cover in your issue / blocker note:"}
              </p>
              <ul class="record-tips__list">
                <%= if @report_type == "daily_progress" do %>
                  <li>Work completed today</li>
                  <li>Crew size on site</li>
                  <li>Weather and any delays</li>
                  <li>Materials used and what's still needed</li>
                  <li>Any blockers or problems</li>
                  <li>Plan for tomorrow</li>
                <% else %>
                  <li>What the problem is</li>
                  <li>Severity — low, medium, high, or critical</li>
                  <li>Which work is affected</li>
                  <li>What action you need</li>
                  <li>Whether a deadline is at risk</li>
                <% end %>
              </ul>
            </div>

            <div class="recorder">
              <div class="recorder__actions">
                <button type="button" id="fs-record-btn" class="recorder__btn">
                  <span class="recorder__dot" aria-hidden="true"></span>
                  <span class="recorder__label">Tap to record</span>
                </button>
                <button type="button" id="fs-submit-btn" class="primary-btn" disabled>
                  Submit report
                </button>
              </div>
              <p id="fs-record-status" class="recorder__status" aria-live="polite"></p>
              <audio id="fs-record-preview" controls hidden></audio>
            </div>
          </form>
        </section>

        <section class="panel panel--feed">
          <h2>Reports</h2>
          <div id="fs-feed" phx-update="stream" class="feed">
            <article
              :for={{dom_id, report} <- @streams.reports}
              id={dom_id}
              class={"card card--#{report.status}"}
            >
              <header class="card__head">
                <div class="card__head-top">
                  <span class="card__type">{humanize_key(report.report_type || "report")}</span>
                  <span class={"fs-status fs-status--#{report.status}"}>{report.status}</span>
                </div>
                <span class="card__meta">{report.supervisor} @ {project_name(@projects, report.project_id)}</span>
              </header>
              <%= if report.transcript do %>
                <p class="card__transcript">
                  {String.slice(report.transcript, 0, 200)}{if String.length(report.transcript) > 200,
                    do: "…",
                    else: ""}
                </p>
              <% end %>
              <%= if has_structured?(report.structured_data) do %>
                <dl class="card__fields">
                  <%= for {key, val} <- report.structured_data,
                          key != "raw_transcript",
                          not is_nil(val),
                          val != [] do %>
                    <div class="card__field">
                      <dt>{humanize_key(key)}</dt>
                      <dd>{format_field_value(val)}</dd>
                    </div>
                  <% end %>
                </dl>
              <% end %>
              <%= if report.error_log not in [nil, []] do %>
                <ul class="card__errors">
                  <%= for entry <- report.error_log do %>
                    <li class={"card__errors-item card__errors-item--#{entry_severity(entry)}"}>
                      <span class="card__errors-stage">{entry["stage"]}</span>
                      <span class="card__errors-kind">{entry["kind"]}</span>
                      <%= if entry["reason"] do %>
                        <span class="card__errors-reason">{entry["reason"]}</span>
                      <% end %>
                    </li>
                  <% end %>
                </ul>
              <% end %>
              <footer class="card__foot">
                <%= if report.sheet_row_url do %>
                  <a href={report.sheet_row_url} target="_blank" rel="noopener">→ Sheet row</a>
                <% end %>
              </footer>
            </article>
          </div>
        </section>

        <section class="panel panel--arch">
          <h2>Infrastructure</h2>

          <svg
            viewBox="0 0 360 340"
            class="arch-svg"
            xmlns="http://www.w3.org/2000/svg"
            aria-label="Infrastructure diagram"
          >
            <defs>
              <marker id="arrow" markerWidth="10" markerHeight="10" refX="9" refY="3" orient="auto">
                <path d="M0,0 L0,6 L9,3 z" fill="currentColor" />
              </marker>
            </defs>

            <g class="arch-container">
              <rect x="4" y="4" width="352" height="192" rx="12" />
              <text x="180" y="24" text-anchor="middle" class="arch-label">Elixir</text>
              <line x1="4" y1="36" x2="356" y2="36" class="arch-sep" />
            </g>

            <g class="node" data-id="browser">
              <rect x="120" y="44" width="120" height="52" rx="8" />
              <text x="180" y="63" text-anchor="middle">Browser</text>
              <text x="180" y="80" text-anchor="middle" class="node__sub">records voice note</text>
            </g>

            <g class="node" data-id="orchestrator">
              <rect x="80" y="120" width="200" height="60" rx="8" />
              <text x="180" y="146" text-anchor="middle">Orchestrator</text>
              <text x="180" y="163" text-anchor="middle" class="node__sub">runs the pipeline</text>
            </g>

            <g class="node" data-id="openai">
              <rect x="14" y="216" width="148" height="52" rx="8" />
              <text x="88" y="238" text-anchor="middle">OpenAI</text>
              <text x="88" y="256" text-anchor="middle" class="node__sub">Whisper + GPT</text>
            </g>

            <g class="node" data-id="apps_script">
              <rect x="198" y="216" width="148" height="52" rx="8" />
              <text x="272" y="245" text-anchor="middle">Apps Script</text>
            </g>

            <g class="node" data-id="sheets">
              <rect x="198" y="284" width="148" height="42" rx="8" />
              <text x="272" y="310" text-anchor="middle">Google Sheets</text>
            </g>

            <line x1="180" y1="96" x2="180" y2="120" stroke="currentColor" marker-end="url(#arrow)" />
            <line x1="124" y1="180" x2="78" y2="216" stroke="currentColor" marker-end="url(#arrow)" />
            <line x1="92" y1="216" x2="138" y2="180" stroke="currentColor" marker-end="url(#arrow)" />
            <line x1="252" y1="180" x2="272" y2="216" stroke="currentColor" marker-end="url(#arrow)" />
            <line x1="272" y1="268" x2="272" y2="284" stroke="currentColor" marker-end="url(#arrow)" />
          </svg>

          <nav class="explainer">
            <button
              type="button"
              class={tab_class(@explainer_tab, "elixir")}
              phx-click="explainer_tab"
              phx-value-tab="elixir"
            >
              Elixir?
            </button>
            <button
              type="button"
              class={tab_class(@explainer_tab, "openai")}
              phx-click="explainer_tab"
              phx-value-tab="openai"
            >
              OpenAI usage
            </button>
            <button
              type="button"
              class={tab_class(@explainer_tab, "apps_script")}
              phx-click="explainer_tab"
              phx-value-tab="apps_script"
            >
              Apps Script integration
            </button>
          </nav>

          <article :if={@explainer_tab == "elixir"} class="explainer__body">
            <p>
              <a href="https://elixir-lang.org/" target="_blank" rel="noopener">Elixir</a>
              is the programming language running this application. It sits between
              the browser, OpenAI, and Google, receiving voice notes,
              coordinating steps, and updating the page.
            </p>
            <p>
              It plays the same connecting role that Zapier would, but with more
              fine-grained control over behaviour and error handling.
            </p>
            <p class="explainer__lead">Where this beats Zapier:</p>
            <ul class="explainer__list">
              <li>
                Zero added cost of creating a website to capture and display data,
                with much more flexibility than Zapier Forms.
              </li>
              <li>
                At each successful step in the processing pipeline, a live update is
                sent to the website so users can confirm a successful upload.
              </li>
              <li>
                When a step fails, the system pauses before trying again, waiting
                a little longer each time. This retry behaviour is configurable and can be customised.
              </li>
              <li>
                The running cost is the same whether ten reports come in or a thousand.
                There's no per-submission fee that grows with the team.
              </li>
            </ul>
            <p>
              Zapier is still the right call when a workflow is simple and the people
              running it don't write code. This one has enough moving parts that it
              made sense to build it properly.
            </p>
          </article>
          <article :if={@explainer_tab == "openai"} class="explainer__body">
            <p>
              OpenAI handles two distinct steps. First, the audio is sent to
              Whisper, which converts it to plain text. A 30-second clip comes
              back as a full written transcript in a few seconds.
            </p>
            <p>
              That transcript is then passed to a second model with instructions
              that vary depending on the report type:
            </p>
            <ul class="explainer__list">
              <li>
                <strong>Daily progress</strong> — extracts what work was done,
                crew size, weather impact, materials used and what&apos;s still
                needed, any blockers, and tomorrow&apos;s plan.
              </li>
              <li>
                <strong>Issue / blocker</strong> — extracts a summary of the
                problem, its severity, which work is affected, the action
                requested, and whether there&apos;s a deadline at risk.
              </li>
            </ul>
            <p>
              The model is told exactly what fields to return and what shape
              each one should take, so the output is consistent no matter how
              a supervisor phrases things on the day. The original transcript
              is always kept alongside the extracted data — nothing is lost
              in the interpretation.
            </p>
          </article>
          <article :if={@explainer_tab == "apps_script"} class="explainer__body">
            <p>
              When a report is ready, the structured data is sent to a small
              script running inside Google Workspace. That script appends a row
              to the project's Google Sheet. One row per submission, with
              all the extracted fields laid out in readable columns.
            </p>
            <p>
              For this MVP, the intent was to demonstrate my comfort using Google Workspace
              tools. It would be straightforward to extend this to Google Drive or Gmail.
            </p>
          </article>
        </section>
      </main>
    </div>
    """
  end

  defp tab_class(active, id) do
    base = "explainer__tab"
    if active == id, do: base <> " " <> base <> "--active", else: base
  end

  defp project_name(projects, id) do
    case Enum.find(projects, &(&1.id == id)) do
      %{name: name} -> name
      _ -> id
    end
  end

  defp has_structured?(data) when is_map(data) and map_size(data) > 0, do: true
  defp has_structured?(_), do: false

  defp humanize_key(key) do
    key |> String.split("_") |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_field_value(val) when is_list(val) do
    val |> Enum.map(&format_list_item/1) |> Enum.join(", ")
  end

  defp format_field_value(val) when is_binary(val), do: val
  defp format_field_value(val) when is_integer(val), do: Integer.to_string(val)
  defp format_field_value(val) when is_float(val), do: :erlang.float_to_binary(val, decimals: 1)
  defp format_field_value(val), do: inspect(val)

  defp format_list_item(%{"item" => item}), do: item
  defp format_list_item(val) when is_binary(val), do: val
  defp format_list_item(val), do: inspect(val)

  defp entry_severity(%{"kind" => "apps_script_skipped"}), do: "info"
  defp entry_severity(%{"kind" => "json_decode"}), do: "warn"
  defp entry_severity(_), do: "error"

  # Add or replace a report in the per-device submissions list. Used when
  # this browser kicks off a new submission so the panel shows it
  # immediately rather than waiting for a re-mount + localStorage rehydrate.
  defp upsert_recent(socket, report) do
    next = [report | Enum.reject(socket.assigns.recent_user_submissions, &(&1.id == report.id))]
    assign(socket, :recent_user_submissions, next)
  end

  # Replace an existing entry on PubSub broadcast so the panel reflects
  # status, transcript, and downstream link changes. Reports that aren't
  # in this device's local list are ignored — the feed panel handles them.
  defp refresh_recent(socket, report) do
    current = socket.assigns.recent_user_submissions

    if Enum.any?(current, &(&1.id == report.id)) do
      assign(
        socket,
        :recent_user_submissions,
        Enum.map(current, fn r -> if r.id == report.id, do: report, else: r end)
      )
    else
      socket
    end
  end
end
