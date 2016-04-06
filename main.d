module screentool;

import std.conv: text;
import std.file: read;
import std.format: formattedRead;
import std.process: environment, execute, pipeProcess, Redirect;
import std.string: chomp;

import std.json;
import std.stdio;

/*

    Screenshots:
    ✔ select area
    - current window [padding]
    - current screen
    - all screens

    - format
    - magnifier

    - take directly, edit later

    - assign name
    - save to local folder
    ✔ open feh
    ✔ upload
      ✔ copy url to clipboard

    Uploaders:
    ✔ novaember
    - imgur
    - a pomf clone

*/

struct SlopResult
{
    int x, y, w, h, windowId;
    string geometry;
}

int main(string[] args)
{
    // Program input
    string   selector = args[1];
    string[] actions  = args[2..$];


    // Stage one: selection

    string geometry;

    switch (selector)
    {
        case "select-area":
            geometry = area_selectArea();
            break;
        case "test":
            geometry = area_test();
            break;
        default:
            writeln("Unknown selector " ~ selector);
            return 1;
    }


    // Stage two: capture

    string filepath = "/tmp/screenshot.png";

    string[] maimCmdline = [ "maim", "-g", geometry, filepath ];

    auto maim = execute(maimCmdline);

    if (maim.status != 0)
    {
        write(maim.output);
        return maim.status;
    }


    // Stage three: actions

    foreach (action; actions) switch (action)
    {
        case "upload":
            // TODO: Optionally read directly from env var
            string secret = read(environment.get("HOME") ~ "/.nvsecret").text.chomp;

            // TODO: Use libcurl
            auto curl = execute([ "curl", "-s", "http://status.novaember.com/image",
                    "-F", "file=@" ~ filepath,
                    "-F", "secret=" ~ secret ]);

            // TODO: Handle issues
            JSONValue json = parseJSON(curl.output);
            string url = json["url"].str;

            auto xclipPrimary   = pipeProcess([ "xclip", "-selection", "primary"   ], Redirect.stdin);
            auto xclipClipboard = pipeProcess([ "xclip", "-selection", "clipboard" ], Redirect.stdin);

            xclipPrimary.stdin.write(url);
            xclipClipboard.stdin.write(url);

            break;

        case "feh":
            execute([ "feh", filepath ]);
            break;

        default:
            writeln("Unknown action " ~ action);
            break;
    }

    return 0;
}

string area_selectArea()
{
    auto slop = execute([ "slop", "--nokeyboard", "-c", "1,0.68,0", "-b", "1" ]);

    if (slop.status != 0)
    {
        write(slop.output);
        return "";
    }

    SlopResult slopResult;

    formattedRead(slop.output, "X=%d\nY=%d\nW=%d\nH=%d\nG=%s\nID=%d\n",
            &slopResult.x,
            &slopResult.y,
            &slopResult.w,
            &slopResult.h,
            &slopResult.geometry,
            &slopResult.windowId);

    return slopResult.geometry;
}

string area_test()
{
    return "200x100+50+50";
}
