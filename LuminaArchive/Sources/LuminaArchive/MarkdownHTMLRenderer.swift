import Foundation

enum MarkdownHTMLRenderer {
    static func render(_ markdown: String) -> String {
        let body = blocks(from: markdown)
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              --text: #141412;
              --secondary: #6B6B68;
              --accent: #3C6F6B;
              --accent-bg: rgba(60,111,107,0.06);
              --border: rgba(0,0,0,.055);
              --surface: #FFFFFF;
              --soft: #F5F3EE;
              --rule: rgba(0,0,0,.07);
            }
            @media (prefers-color-scheme: dark) {
              :root {
                --text: #ECECEA;
                --secondary: #B7B7B2;
                --accent: #7ABAB3;
                --accent-bg: rgba(122,186,179,0.12);
                --border: rgba(255,255,255,.10);
                --surface: #28292B;
                --soft: #36383A;
                --rule: rgba(255,255,255,.12);
              }
            }
            html, body {
              margin: 0; padding: 0;
              background: var(--surface);
              color: var(--text);
              font: 14px/1.7 -apple-system, "SF Pro Text", sans-serif;
              -webkit-font-smoothing: antialiased;
            }
            body { padding: 24px 22px 48px; box-sizing: border-box; }

            h1 {
              font-size: 44px;
              line-height: 1.0;
              font-weight: 200;
              letter-spacing: -0.025em;
              margin: 0 0 4px;
              color: var(--text);
            }
            .subtitle {
              font-size: 13px;
              color: var(--secondary);
              margin: 0 0 36px;
              font-weight: 400;
              letter-spacing: 0.01em;
            }
            h2 {
              font-size: 9px;
              font-weight: 700;
              letter-spacing: 0.15em;
              text-transform: uppercase;
              color: var(--accent);
              margin: 36px 0 12px;
              padding-bottom: 7px;
              border-bottom: 1px solid var(--rule);
            }
            h3 {
              font-size: 9px;
              font-weight: 600;
              letter-spacing: 0.10em;
              text-transform: uppercase;
              color: var(--secondary);
              margin: 24px 0 8px;
            }
            p { margin: 0 0 12px; }
            strong { font-weight: 600; color: var(--text); }
            a { color: var(--accent); text-decoration-thickness: 1px; text-underline-offset: 2px; }
            img { display: block; max-width: 100%; height: auto; margin: 16px 0 22px; border-radius: 8px; }
            blockquote {
              margin: 12px 0 18px;
              padding: 8px 0 8px 16px;
              border-left: 3px solid var(--accent);
              color: var(--secondary);
            }
            hr { border: 0; border-top: 1px solid var(--rule); margin: 26px 0; }
            ul { margin: 0 0 16px; padding: 0; list-style: none; }
            li { padding: 4px 0 4px 16px; position: relative; font-size: 13.5px; }
            li::before { content: "–"; position: absolute; left: 0; color: var(--accent); }

            .table-wrap { overflow-x: auto; margin: 12px 0 24px; }
            table { width: 100%; border-collapse: collapse; font-size: 13px; }
            th {
              text-align: left;
              font-size: 9px;
              font-weight: 700;
              letter-spacing: 0.10em;
              text-transform: uppercase;
              color: var(--secondary);
              padding: 0 12px 8px 0;
              border-bottom: 1px solid var(--rule);
              white-space: nowrap;
            }
            td {
              padding: 7px 12px 7px 0;
              vertical-align: top;
              border-bottom: 1px solid var(--border);
              line-height: 1.5;
            }
            td:first-child {
              white-space: nowrap;
              color: var(--secondary);
              font-size: 12px;
              min-width: 56px;
            }
            tr:last-child td { border-bottom: 0; }
            code {
              font-family: ui-monospace, "SF Mono", Menlo, monospace;
              font-size: 0.87em;
              background: var(--soft);
              padding: 2px 6px;
              border-radius: 4px;
            }
          </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func blocks(from markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var html: [String] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var index = 0
        var nextParaIsSubtitle = false

        func flushParagraph() {
            if !paragraph.isEmpty {
                let classAttribute = nextParaIsSubtitle ? " class=\"subtitle\"" : ""
                html.append("<p\(classAttribute)>\(inline(paragraph.joined(separator: " ")))</p>")
                nextParaIsSubtitle = false
                paragraph.removeAll()
            }
        }

        func flushList() {
            if !listItems.isEmpty {
                html.append("<ul>\(listItems.map { "<li>\($0)</li>" }.joined())</ul>")
                listItems.removeAll()
            }
        }

        while index < lines.count {
            let raw = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
                flushList()
                index += 1
                continue
            }

            if isTableStart(lines, at: index) {
                flushParagraph()
                flushList()
                nextParaIsSubtitle = false
                let parsed = parseTable(lines, from: index)
                html.append(parsed.html)
                index = parsed.nextIndex
                continue
            }

            if line.hasPrefix("# ") {
                flushParagraph()
                flushList()
                html.append("<h1>\(inline(String(line.dropFirst(2))))</h1>")
                nextParaIsSubtitle = true
            } else if line.hasPrefix("## ") {
                flushParagraph()
                flushList()
                nextParaIsSubtitle = false
                html.append("<h2>\(inline(String(line.dropFirst(3))))</h2>")
            } else if line.hasPrefix("### ") {
                flushParagraph()
                flushList()
                nextParaIsSubtitle = false
                html.append("<h3>\(inline(String(line.dropFirst(4))))</h3>")
            } else if line == "---" || line == "***" {
                flushParagraph()
                flushList()
                nextParaIsSubtitle = false
                html.append("<hr>")
            } else if line.hasPrefix("> ") {
                flushParagraph()
                flushList()
                nextParaIsSubtitle = false
                html.append("<blockquote>\(inline(String(line.dropFirst(2))))</blockquote>")
            } else if line.hasPrefix("- ") {
                flushParagraph()
                nextParaIsSubtitle = false
                listItems.append(inline(String(line.dropFirst(2))))
            } else {
                flushList()
                if raw.hasSuffix("  ") {
                    flushParagraph()
                    let classAttribute = nextParaIsSubtitle ? " class=\"subtitle\"" : ""
                    html.append("<p\(classAttribute)>\(inline(line))</p>")
                    nextParaIsSubtitle = false
                } else {
                    paragraph.append(line)
                }
            }
            index += 1
        }

        flushParagraph()
        flushList()
        return html.joined(separator: "\n")
    }

    private static func isTableStart(_ lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
        return header.contains("|") && separator.range(of: #"^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$"#, options: .regularExpression) != nil
    }

    private static func parseTable(_ lines: [String], from start: Int) -> (html: String, nextIndex: Int) {
        let headers = tableCells(lines[start])
        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard line.contains("|"), !line.isEmpty else { break }
            rows.append(tableCells(line))
            index += 1
        }

        let head = headers.map { "<th>\(inline($0))</th>" }.joined()
        let body = rows.map { row in
            "<tr>\(row.map { "<td>\(inline($0))</td>" }.joined())</tr>"
        }.joined()
        return ("<div class=\"table-wrap\"><table><thead><tr>\(head)</tr></thead><tbody>\(body)</tbody></table></div>", index)
    }

    private static func tableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
    }

    private static func inline(_ text: String) -> String {
        var output = escape(text)
        output = output.replacingOccurrences(
            of: #"!\[([^\]]*)\]\(([^)]+)\)"#,
            with: #"<img src="$2" alt="$1">"#,
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: #"<a href="$2">$1</a>"#,
            options: .regularExpression
        )
        output = output.replacingOccurrences(of: #"`([^`]+)`"#, with: "<code>$1</code>", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        return output
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
