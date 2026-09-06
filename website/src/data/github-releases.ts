export type ReleasePlatform = "macos" | "windows";

interface GitHubReleaseResponse {
  tag_name: string;
  name: string | null;
  body: string | null;
  html_url: string;
  published_at: string | null;
  draft: boolean;
  prerelease: boolean;
}

export interface ParsedReleaseSection {
  heading: string;
  paragraphs: string[];
  items: string[];
}

export interface ParsedGitHubRelease {
  version: string;
  url: string;
  publishedAt: string;
  introduction: string[];
  sections: ParsedReleaseSection[];
}

const RELEASES_URL = "https://api.github.com/repos/sidey-app/SIDEY/releases?per_page=100";
let releasesRequest: Promise<GitHubReleaseResponse[]> | undefined;

function cleanInlineMarkdown(value: string) {
  return value
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1")
    .replace(/[*_~`]/g, "")
    .replace(/\\([\\`*_[\]{}()#+\-.!])/g, "$1")
    .trim();
}

function parseReleaseBody(body: string | null) {
  const introduction: string[] = [];
  const sections: ParsedReleaseSection[] = [];
  let section: ParsedReleaseSection | undefined;
  let paragraph: string[] = [];

  const flushParagraph = () => {
    if (paragraph.length === 0) return;
    const value = cleanInlineMarkdown(paragraph.join(" "));
    if (value) (section?.paragraphs ?? introduction).push(value);
    paragraph = [];
  };

  for (const rawLine of (body ?? "").split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) {
      flushParagraph();
      continue;
    }
    if (/^#\s+/.test(line)) continue;
    if (/^`[^`]+`(?:\s*[·|]\s*`[^`]+`)*$/.test(line)) continue;
    const heading = line.match(/^##\s+(.+)$/);
    if (heading) {
      flushParagraph();
      section = { heading: cleanInlineMarkdown(heading[1]), paragraphs: [], items: [] };
      sections.push(section);
      continue;
    }
    const item = line.match(/^[-*]\s+(.+)$/);
    if (item) {
      flushParagraph();
      if (!section) {
        section = { heading: "", paragraphs: [], items: [] };
        sections.push(section);
      }
      section.items.push(cleanInlineMarkdown(item[1]));
      continue;
    }
    paragraph.push(line.replace(/^>\s?/, ""));
  }
  flushParagraph();

  return { introduction, sections: sections.filter((item) => item.heading || item.paragraphs.length || item.items.length) };
}

async function fetchReleases() {
  if (!releasesRequest) {
    const token = import.meta.env.GITHUB_TOKEN ?? import.meta.env.GH_TOKEN;
    releasesRequest = fetch(RELEASES_URL, {
      headers: {
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "SIDEY-website",
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
    }).then(async (response) => {
      if (!response.ok) throw new Error(`GitHub Releases request failed: ${response.status} ${response.statusText}`);
      return response.json() as Promise<GitHubReleaseResponse[]>;
    });
  }
  return releasesRequest;
}

export async function getGitHubReleases(platform: ReleasePlatform, limit = 100): Promise<ParsedGitHubRelease[]> {
  const tagPattern = platform === "macos" ? /^v(\d+(?:\.\d+)+)$/ : /^windows-v(\d+(?:\.\d+)+)$/;
  const releases = await fetchReleases();
  const platformReleases = releases
    .filter((release) => !release.draft && !release.prerelease && tagPattern.test(release.tag_name))
    .slice(0, limit)
    .map((release) => {
      const version = release.tag_name.match(tagPattern)?.[1] ?? release.tag_name;
      const parsed = parseReleaseBody(release.body);
      return {
        version,
        url: release.html_url,
        publishedAt: release.published_at ?? "",
        introduction: parsed.introduction,
        sections: parsed.sections,
      };
    });

  if (platformReleases.length === 0) {
    throw new Error(`No published GitHub Releases found for ${platform}.`);
  }
  return platformReleases;
}
