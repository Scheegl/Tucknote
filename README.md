# Tucknote

A local inbox for thoughts, links, and small tasks. Requires macOS 13 or later on Apple Silicon.

## Install

**Download:** The first notarized app download is pending. When available, the [Releases](https://github.com/Scheegl/tucknote/releases) page will list `Tucknote-…-macos-arm64.zip` under **Assets**. Unzip it, drag `Tucknote.app` into **Applications**, and open it. The separate **Source code** archives contain the project files.

**Build from source:** Clone this repository using the URL under **Code**. On an Apple Silicon Mac with macOS 13 or later and Apple Command Line Tools, run `./build.sh` from the checkout. Open `build/Tucknote.app` or copy it into **Applications**.

## Use Tucknote

Double-click Tucknote.app in Finder. Click the pocket icon in the menu bar to capture an entry, or hold **Control** and **Option** and press **Space**. Then paste with **Command + V** or **Control + V** and press **Return** to save. You can assign a category before saving. Right-click any entry in quick capture or the full Inbox to change its category immediately, edit its details, or open and copy its link.

Right-click the menu bar icon for **Open Inbox**, **Refresh Link Titles**, **Settings**, and **Quit Tucknote**. The Settings and Quit buttons are also available from quick capture. In Settings, choose **System**, **Light**, or **Dark**. System follows macOS.

The full Inbox searches across all sections, including Archive and Completed. Click a source tag to filter all entries from that site. Use **Up** or **Down** to select a row, **Return** to edit it, and **Command + Shift + A** to archive an active entry. In quick capture, the circle at the start marks an entry complete, and **…** opens its actions.

If a link is already saved, **Show Entry** opens the existing entry in its section. YouTube watch URLs, short links, Shorts, and embed URLs for the same video count as duplicates.

The full Inbox also supports editing, notes, and undo for the most recent deletion. Settings also controls the inbox count and launch at login.

## Storage and links

Entries are stored locally in `~/Library/Application Support/Laterfold/inbox.json`. Writes are atomic. If the file cannot be read, Tucknote shows its location and leaves it available for recovery.

HTTP and HTTPS links save immediately. Title fetching uses HTTPS and is off by default. To fetch titles, choose **Refresh Link Titles** or enable **Fetch link titles automatically** in Settings. Rows show an automatic site tag, such as `youtube`, `x.com`, or `linkedin`. When titles are unavailable, the links stay clickable. Use **Refresh Link Titles** to retry missing or generic titles for saved links. Manually edited titles are preserved. Plain text capture works offline.

## Contribute

Report bugs and suggest improvements in **Issues**. See [CONTRIBUTING.md](CONTRIBUTING.md) for pull requests, [SECURITY.md](SECURITY.md) for private vulnerability reports and link-fetching details, and the [release guide](Tools/RELEASING.md) for packaging.

Tucknote is available under the [MIT License](LICENSE).

Direct capture of the current browser tab is deferred. Browser automation for Safari or Chrome would require Automation permission.
