import requests
import json
import time
import sys
import os
import argparse
import logging
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from rich.console import Console
from rich.prompt import Prompt, Confirm
from rich.panel import Panel
from rich.progress import (
    Progress,
    SpinnerColumn,
    TextColumn,
    BarColumn,
    TaskProgressColumn,
    TimeElapsedColumn,
)
from rich.syntax import Syntax
from rich.table import Table
from rich import box
from rich.align import Align
from rich.rule import Rule
from rich.text import Text
from rich.columns import Columns


def _enable_utf8_stdio_on_windows():
    if os.name != "nt":
        return
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except Exception:
            pass


_enable_utf8_stdio_on_windows()

console = Console()

# Logging
log_formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")
logger = logging.getLogger("uni_watch")
logger.setLevel(logging.DEBUG)

file_handler = logging.FileHandler("api_responses.log", "w", encoding="utf-8")
file_handler.setFormatter(log_formatter)
logger.addHandler(file_handler)

BASE_URL = "https://online.vtu.ac.in/api/v1"

# ── Color Palette ─────────────────────────────────────
P = "#c084fc"       # purple  — primary brand
I = "#818cf8"       # indigo  — secondary
C = "#22d3ee"       # cyan    — accent
G = "#4ade80"       # green   — success
A = "#fbbf24"       # amber   — warning
R = "#f87171"       # red     — error
S = "#94a3b8"       # slate   — muted / rules
DIM = "#64748b"     # dim slate

LOGO = f"""\
[bold {P}]██████╗ ██████╗  ██████╗  ██████╗ ██████╗ ███████╗███████╗███████╗[/]
[bold {P}]██╔══██╗██╔══██╗██╔═══██╗██╔════╝ ██╔══██╗██╔════╝██╔════╝██╔════╝[/]
[bold {I}]██████╔╝██████╔╝██║   ██║██║  ███╗██████╔╝█████╗  ███████╗███████╗[/]
[bold {I}]██╔═══╝ ██╔══██╗██║   ██║██║   ██║██╔══██╗██╔══╝  ╚════██║╚════██║[/]
[bold {C}]██║     ██║  ██║╚██████╔╝╚██████╔╝██║  ██║███████╗███████║███████║[/]
[bold {C}]╚═╝     ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝[/]"""

SUBTITLE = (
    f"[bold {P}]Uni Watch Auto-Progress[/]  "
    f"[{DIM}]v0.1.78  •  Fast  •  Parallel  •  Smart[/]"
)


def phase_rule(icon, title, color=S):
    """Print a styled section divider."""
    console.print()
    console.print(Rule(f"[bold {P}]{icon}  {title}[/]", style=color, align="left"))
    console.print()


class UniWatchBypasser:
    def __init__(self, email, password):
        self.email = email
        self.password = password
        self.session = requests.Session()
        self.session.headers.update(
            {
                "Accept": "application/json",
                "Content-Type": "application/json",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                "Origin": "https://online.vtu.ac.in",
                "Referer": "https://online.vtu.ac.in/",
            }
        )
        self._network_lock = threading.Lock()

    def login(self):
        login_url = f"{BASE_URL}/auth/login"
        payload = {"email": self.email, "password": self.password}

        try:
            response = self.session.post(login_url, json=payload)
            data = response.json()
            logger.info(
                f"Login Response: HTTP {response.status_code} | Body: {json.dumps(data)}"
            )

            if response.status_code == 200 and data.get("success"):
                user_name = data.get("data", {}).get("name", "User")
                return True, user_name
            else:
                msg = data.get("message", "Unknown Error")
                return False, msg
        except Exception as e:
            logger.error(f"Login Error: {e}", exc_info=True)
            return False, str(e)

    def get_enrolled_courses(self):
        enrollments_url = f"{BASE_URL}/student/my-enrollments"
        try:
            response = self.session.get(enrollments_url)
            data = response.json()
            if response.status_code == 200 and data.get("success"):
                return data.get("data", [])
        except Exception as e:
            logger.error(f"Enrollments Error: {e}", exc_info=True)
        return []

    def get_course_details(self, course_slug):
        course_url = f"{BASE_URL}/student/my-courses/{course_slug}"
        try:
            response = self.session.get(course_url)
            data = response.json()
            if response.status_code == 200 and data.get("success"):
                return data.get("data", {})
        except Exception as e:
            logger.error(f"Course Details Error for {course_slug}: {e}", exc_info=True)
        return None

    def _wait_for_network(self):
        """Block until network connectivity is restored. Thread-safe."""
        with self._network_lock:
            # Quick re-check — another thread may have already recovered
            try:
                requests.head("https://online.vtu.ac.in", timeout=5)
                return
            except (requests.ConnectionError, requests.Timeout):
                pass

            console.print(
                Panel(
                    Align.center(
                        f"[bold {R}]⚠  Network connection lost[/]\n\n"
                        f"[{DIM}]Polling every 3 seconds until it's back…[/]"
                    ),
                    border_style=R,
                    box=box.ROUNDED,
                    padding=(1, 4),
                )
            )

            while True:
                time.sleep(3)
                try:
                    requests.head("https://online.vtu.ac.in", timeout=5)
                    console.print(
                        f"  [{G}]✔  Network restored — resuming automatically[/]\n"
                    )
                    return
                except (requests.ConnectionError, requests.Timeout):
                    continue

    def mark_video_complete(self, course_slug, lecture_id, progress_ctx, task_id):
        progress_url = (
            f"{BASE_URL}/student/my-courses/{course_slug}"
            f"/lectures/{lecture_id}/progress"
        )

        max_attempts = 150
        current_time = 0

        for attempt in range(1, max_attempts + 1):
            current_time += 120
            payload = {
                "current_time_seconds": current_time,
                "total_duration_seconds": 3600,
                "seconds_just_watched": 120,
            }

            try:
                response = self.session.post(progress_url, json=payload)
                res_data = response.json()
                data_dict = res_data.get("data", {})

                is_completed = data_dict.get("is_completed", False)
                percent = data_dict.get("percent", 0)

                logger.info(
                    f"Progress Ping ({lecture_id}) Att {attempt}: "
                    f"HTTP {response.status_code} | Body: {json.dumps(res_data)}"
                )

                progress_ctx.update(task_id, completed=percent)

                if is_completed or percent >= 98:
                    progress_ctx.update(task_id, completed=100)
                    return True, percent

                if attempt == max_attempts:
                    return False, percent

                time.sleep(0.5)

            except (requests.ConnectionError, requests.Timeout):
                logger.error(
                    f"Network error on lecture {lecture_id}, attempt {attempt}"
                )
                self._wait_for_network()
                current_time -= 120
                continue

            except Exception as e:
                logger.error(
                    f"Progress Ping Error ({lecture_id}): {e}", exc_info=True
                )
                return False, -1

        return False, 0


def _process_lecture(bypasser, course_slug, lecture_id, lecture_title, progress, task_id):
    """Worker function for parallel lecture processing."""
    success, percent = bypasser.mark_video_complete(
        course_slug, lecture_id, progress, task_id
    )

    if success:
        progress.update(
            task_id,
            description=f"[bold {G}]✔  {lecture_title}[/]",
        )
    elif percent == -1:
        progress.update(
            task_id,
            description=f"[bold {R}]✖  {lecture_title}  [dim](error)[/dim][/]",
        )
    else:
        progress.update(
            task_id,
            description=f"[bold {A}]⚠  {lecture_title}  [dim](capped {percent}%)[/dim][/]",
        )

    return {
        "course_slug": course_slug,
        "lecture_id": lecture_id,
        "lecture_title": lecture_title,
        "success": success,
        "percent": percent,
    }


def select_courses(courses):
    """Prompt user to choose auto-run or manual course selection."""
    console.print(
        f"  [{C}]❶[/]  Auto-run all courses\n"
        f"  [{C}]❷[/]  Select specific courses\n"
    )

    mode = Prompt.ask(
        f"  [bold {C}]›[/] [bold]Choice[/]",
        choices=["1", "2"],
        default="1",
    )

    if mode == "1":
        return courses

    # Manual selection
    console.print()
    for i, enrollment in enumerate(courses, 1):
        details = enrollment.get("details", {})
        prog = enrollment.get("progress_percent", "0")
        console.print(
            f"    [{C}]{i}[/]  {details.get('title', 'Unknown')} "
            f"[{DIM}]· {prog}% done[/]"
        )

    console.print()
    selection = Prompt.ask(
        f"  [bold {C}]›[/] [bold]Enter course numbers[/] [{DIM}]comma-separated[/]"
    )

    try:
        indices = [int(x.strip()) - 1 for x in selection.split(",")]
        selected = [courses[i] for i in indices if 0 <= i < len(courses)]
        if not selected:
            console.print(f"  [{A}]No valid selection — running all courses.[/]")
            return courses
        return selected
    except (ValueError, IndexError):
        console.print(f"  [{A}]Invalid input — running all courses.[/]")
        return courses


def select_workers():
    """Prompt user to choose the number of parallel workers."""
    console.print()
    console.print(
        f"  [bold {A}]⚠  Risk Warning:[/]\n"
        f"  [{DIM}]Workers process videos simultaneously. More workers = faster completion.\n"
        f"  However, using many workers might look unnatural to the portal servers.\n"
        f"  You can choose a maximum of 3 workers for account safety.[/]\n"
    )
    worker_str = Prompt.ask(
        f"  [bold {C}]›[/] [bold]Number of workers[/] [{DIM}]1-3, default 1[/]",
        default="1",
    )
    try:
        workers = int(worker_str)
        if workers < 1:
            workers = 1
        elif workers > 3:
            workers = 3
    except ValueError:
        workers = 1
    return workers


def print_summary(stats, elapsed_secs=None):
    """Print a beautiful summary dashboard."""
    total = stats["total"]
    skipped = stats["skipped"]
    completed = stats["completed"]
    failed = stats["failed"]

    # Build percentage bar
    done_pct = ((skipped + completed) / total * 100) if total else 0

    # Stats grid
    grid = Table.grid(padding=(0, 3))
    grid.add_column(justify="right", style="bold")
    grid.add_column(justify="left")

    grid.add_row(f"[{DIM}]Total Lectures[/]", f"[bold]{total}[/]")
    grid.add_row(f"[{DIM}]Skipped[/] [{DIM}](already done)[/]", f"[{S}]{skipped}[/]")
    grid.add_row(f"[{DIM}]Newly Completed[/]", f"[bold {G}]{completed}[/]")
    grid.add_row(f"[{DIM}]Failed[/]", f"[bold {R}]{failed}[/]" if failed else f"[{G}]0[/]")

    if elapsed_secs is not None:
        mins = int(elapsed_secs // 60)
        secs = int(elapsed_secs % 60)
        grid.add_row(f"[{DIM}]Elapsed Time[/]", f"[{C}]{mins}m {secs}s[/]")

    grid.add_row("", "")
    grid.add_row(
        f"[{DIM}]Coverage[/]",
        f"[bold {G}]{done_pct:.1f}%[/]" if done_pct >= 90 else f"[bold {A}]{done_pct:.1f}%[/]",
    )

    console.print(
        Panel(
            Align.center(grid),
            title=f"[bold {C}]📊  Run Summary[/]",
            border_style=I,
            box=box.ROUNDED,
            padding=(1, 4),
        )
    )


def view_logs():
    if not os.path.exists("api_responses.log"):
        console.print(f"  [{A}]⚠  Log file 'api_responses.log' not found.[/]")
        return

    console.print(
        Panel(
            Align.center(f"[bold {C}]◷  Recent API Response Logs[/]"),
            border_style=C,
            padding=(1, 2),
        )
    )

    with open("api_responses.log", "r", encoding="utf-8") as f:
        lines = f.readlines()
        recent = "".join(lines[-40:])

    syntax = Syntax(recent, "log", theme="monokai", word_wrap=True, line_numbers=True)
    console.print(syntax)


def main():
    parser = argparse.ArgumentParser(description="Online Video Automation CLI")
    parser.add_argument(
        "--log", action="store_true", help="View recent API response logs"
    )
    args = parser.parse_args()

    os.system("cls" if os.name == "nt" else "clear")

    # ── Header ────────────────────────────────────────
    console.print(
        Panel(
            Align.center(f"{LOGO}\n{SUBTITLE}"),
            border_style=P,
            box=box.DOUBLE,
            padding=(1, 4),
        )
    )

    if args.log:
        view_logs()
        sys.exit(0)

    start_time = time.time()

    # ── Phase 1: Authentication ───────────────────────
    phase_rule("🔐", "Authentication")
    
    console.print(f"  [{DIM}]* Login constitutes agreement to LICENSE & T&C (Zero liability)[/]\n")

    email = Prompt.ask(f"  [bold {C}]✉[/]  [bold]Email[/]")
    password = Prompt.ask(f"  [bold {C}]🔑[/] [bold]Password[/]", password=True)

    console.print()

    bypasser = UniWatchBypasser(email, password)

    with console.status(
        f"  [{A}]Authenticating securely…[/]", spinner="dots12"
    ):
        success, msg_or_name = bypasser.login()

    if not success:
        console.print(
            Panel(
                f"[bold {R}]✖  Authentication Failed[/]\n[{DIM}]{msg_or_name}[/]",
                border_style=R,
                box=box.ROUNDED,
                padding=(1, 3),
            )
        )
        sys.exit(1)

    console.print(
        f"  [{G}]✔[/]  Authenticated as [bold {C}]{msg_or_name}[/]\n"
    )

    # ── Phase 2: Course Discovery ─────────────────────
    phase_rule("📚", "Course Discovery")

    with console.status(
        f"  [{A}]Fetching enrolled courses…[/]", spinner="dots12"
    ):
        courses = bypasser.get_enrolled_courses()

    if not courses:
        console.print(
            Panel(
                f"[bold {R}]✖  No enrolled courses found on this account.[/]",
                border_style=R,
            )
        )
        sys.exit(0)

    # Courses table
    table = Table(
        box=box.SIMPLE_HEAVY,
        border_style=I,
        header_style=f"bold {P}",
        row_styles=[f"{DIM}", ""],
        padding=(0, 2),
        show_edge=False,
    )
    table.add_column("#", justify="center", style=C, no_wrap=True, width=4)
    table.add_column("Course", style="bold white", ratio=3)
    table.add_column("Progress", justify="right", style=G, width=12)

    for i, enrollment in enumerate(courses, 1):
        details = enrollment.get("details", {})
        prog = enrollment.get("progress_percent", "0")
        prog_float = float(prog) if prog else 0

        # Color-code progress
        if prog_float >= 90:
            prog_display = f"[bold {G}]{prog}%  ✓[/]"
        elif prog_float >= 50:
            prog_display = f"[{A}]{prog}%[/]"
        else:
            prog_display = f"[{S}]{prog}%[/]"

        table.add_row(str(i), details.get("title", "Unknown"), prog_display)

    console.print(Panel(table, border_style=I, box=box.ROUNDED, padding=(1, 2)))

    # Course selection
    console.print()
    selected_courses = select_courses(courses)

    num_workers = select_workers()

    console.print(
        f"\n  [{DIM}]▸ {len(selected_courses)} course(s) queued  "
        f"·  {num_workers} parallel workers[/]\n"
    )

    # ── Phase 3: Processing ───────────────────────────
    phase_rule("⚡", "Processing")

    stats = {"total": 0, "skipped": 0, "completed": 0, "failed": 0}
    failed_lectures = []

    for enrollment in selected_courses:
        details = enrollment.get("details", {})
        course_slug = details.get("slug")
        course_title = details.get("title")

        if not course_slug:
            continue

        console.print(
            Panel(
                f"  [bold white]{course_title}[/]",
                border_style=P,
                box=box.HEAVY,
                padding=(0, 2),
            )
        )

        with console.status(
            f"  [{DIM}]Loading course contents…[/]", spinner="dots12"
        ):
            course_data = bypasser.get_course_details(course_slug)

        if not course_data:
            console.print(
                f"  [bold {R}]✖  Could not load details for {course_title}[/]"
            )
            continue

        lessons = course_data.get("lessons", [])

        for week in lessons:
            week_name = week.get("name", "Unknown Week")
            lectures = week.get("lectures", [])

            # Split into already-done vs pending
            pending = []
            for lec in lectures:
                stats["total"] += 1
                if lec.get("is_completed", False):
                    stats["skipped"] += 1
                else:
                    pending.append(lec)

            skipped = len(lectures) - len(pending)

            # Week header
            console.print(
                f"\n  [{I}]┌─[/] [bold {I}]{week_name}[/]  "
                f"[{DIM}]{len(lectures)} lectures[/]"
                + (f"  [{G}]·  {skipped} done[/]" if skipped else "")
            )

            if not pending:
                console.print(
                    f"  [{I}]└─[/] [{G}]All lectures already completed  ✓[/]"
                )
                continue

            if skipped > 0:
                console.print(
                    f"  [{I}]│[/]  [{DIM}]↳ {skipped} skipped (already done)[/]"
                )

            # Process pending lectures in parallel
            with Progress(
                SpinnerColumn(style=C),
                TextColumn("  {task.description}"),
                BarColumn(
                    bar_width=30,
                    complete_style=G,
                    finished_style=f"bold {G}",
                    pulse_style=I,
                ),
                TaskProgressColumn(),
                TimeElapsedColumn(),
                console=console,
                transient=False,
            ) as progress:
                futures = {}

                with ThreadPoolExecutor(max_workers=num_workers) as executor:
                    for lec in pending:
                        lid = lec.get("id")
                        ltitle = lec.get("title", f"Lecture {lid}")
                        task_id = progress.add_task(
                            f"[{C}]{ltitle}[/]", total=100, completed=0
                        )

                        future = executor.submit(
                            _process_lecture,
                            bypasser,
                            course_slug,
                            lid,
                            ltitle,
                            progress,
                            task_id,
                        )
                        futures[future] = (lid, ltitle)

                    for future in as_completed(futures):
                        result = future.result()
                        if result["success"]:
                            stats["completed"] += 1
                        else:
                            stats["failed"] += 1
                            failed_lectures.append(result)

            console.print(f"  [{I}]└─[/] [{DIM}]Week complete[/]")

        console.print()

    # ── Phase 4: Results ──────────────────────────────
    elapsed = time.time() - start_time
    phase_rule("📊", "Results")
    print_summary(stats, elapsed)

    # ── Retry failed lectures ─────────────────────────
    if failed_lectures:
        console.print()
        console.print(
            Panel(
                Align.center(
                    f"[bold {A}]⚠  {len(failed_lectures)} lecture(s) failed[/]\n"
                    f"[{DIM}]You can retry them now before exiting.[/]"
                ),
                border_style=A,
                box=box.ROUNDED,
                padding=(1, 3),
            )
        )

        retry = Confirm.ask(
            f"\n  [bold {C}]›[/] [bold]Retry failed lectures?[/]", default=True
        )

        if retry:
            phase_rule("🔄", "Retrying")
            retry_recovered = 0

            with Progress(
                SpinnerColumn(style=C),
                TextColumn("  {task.description}"),
                BarColumn(
                    bar_width=30,
                    complete_style=G,
                    finished_style=f"bold {G}",
                    pulse_style=I,
                ),
                TaskProgressColumn(),
                TimeElapsedColumn(),
                console=console,
                transient=False,
            ) as progress:
                for item in failed_lectures:
                    task_id = progress.add_task(
                        f"[{C}]{item['lecture_title']}[/]", total=100, completed=0
                    )
                    result = _process_lecture(
                        bypasser,
                        item["course_slug"],
                        item["lecture_id"],
                        item["lecture_title"],
                        progress,
                        task_id,
                    )
                    if result["success"]:
                        retry_recovered += 1
                        stats["completed"] += 1
                        stats["failed"] -= 1

            console.print(
                f"\n  [{G}]✔  Recovered {retry_recovered}/{len(failed_lectures)} lectures[/]"
            )

            elapsed = time.time() - start_time
            console.print()
            print_summary(stats, elapsed)

    # ── Done ──────────────────────────────────────────
    console.print()
    console.print(
        Panel(
            Align.center(
                f"[bold {G}]🎉  All done![/]\n"
                f"[{DIM}]Check the online portal to verify your progress.[/]"
            ),
            border_style=G,
            box=box.DOUBLE,
            padding=(1, 4),
        )
    )
    console.print()


if __name__ == "__main__":
    main()
