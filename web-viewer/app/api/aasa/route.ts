import { NextResponse } from "next/server";

// Universal Links manifest. Served at /.well-known/apple-app-site-association
// via the rewrite in next.config.mjs.
export function GET() {
  const teamID = process.env.APPLE_TEAM_ID ?? "TEAMID";
  const bundleID = process.env.APPLE_BUNDLE_ID ?? "app.capsule";

  const body = {
    applinks: {
      details: [
        {
          appIDs: [`${teamID}.${bundleID}`],
          components: [
            { "/": "/c/*", comment: "Capsule deep links" },
          ],
        },
      ],
    },
    webcredentials: {
      apps: [`${teamID}.${bundleID}`],
    },
  };

  return new NextResponse(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}
