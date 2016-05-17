module screentool;

import std.algorithm;
import std.conv;
import std.file;
import std.format;
import std.getopt;
import std.json;
import std.process;
import std.regex;
import std.range;
import std.stdio;
import std.string;

import x11.X;
import x11.Xlib;

import uploaders;

/*

    Screenshots:
    ✔ select area
    ✔ current window [padding]
    ✔ current screen
    ✔ all screens

    - format
    - magnifier

    - take directly, edit later

    - assign name
    - save to local folder
    ✔ open feh
    ✔ upload
      ✔ copy url to clipboard
      ✔ show notification

    Uploaders:
    ✔ novaember
    - imgur
    - a pomf clone

*/

enum Selector
{
    area,
    window,
    screen,
    full
}

enum UploadTarget
{
    novaember,
    imgur,
    pomf
}

struct Geometry
{
    uint width, height;
    int x, y;

    static Geometry opCall(string str)
    {
        auto match = str.matchFirst(regex(r"(\d+)x(\d+)\+(\d+)\+(\d+)"));

        Geometry g;
        if (!match) return g;

        g.width = match[1].to!uint;
        g.height = match[2].to!uint;
        g.x = match[3].to!int;
        g.y = match[4].to!int;
        return g;
    }

    static Geometry opCall(uint width, uint height, int x, int y)
    {
        Geometry g;
        g.width = width;
        g.height = height;
        g.x = x;
        g.y = y;
        return g;
    }

    static Geometry opCall(Geometry a, Geometry b)
    {
        int x = min(a.x, b.x);
        int y = min(a.y, b.y);

        int right  = max(a.x + a.width,  b.x + b.width);
        int bottom = max(a.y + a.height, b.y + b.height);

        uint width  = right - x;
        uint height = bottom - y;

        return Geometry(width, height, x, y);
    }

    bool containsPoint(int x, int y)
    {
        return ( x > this.x && y > this.y
              && x < this.x + this.width
              && y < this.y + this.height );
    }

    ulong area()
    {
        return this.width * this.height;
    }

    string str()
    {
        return format("%dx%d%+d%+d", width, height, x, y);
    }
}

struct ScreentoolOptions
{
    UploadTarget[] uploadTargets;
    bool printUploadTargets;

    bool slop;
    bool captureWindow;
    bool captureScreen;
    bool captureEverything;
    bool quiet;
    bool shortURL;

    bool validate(ref string message)
    {
        switch ([ slop, captureWindow, captureScreen, captureEverything ].sum)
        {
            case 0:
                captureEverything = true;
                break;
            case 1:
                break;
            default:
                message = "Can't take more than one of -s, -W, -S, -D!";
                return false;
        }

        assert([ slop, captureWindow, captureScreen, captureEverything ].sum == 1);

        return true;
    }
}

ScreentoolOptions options;

int main(string[] args)
{
    if (args.length < 2) {
        writefln("Error: no options specified, try running %s -h", args[0]);
        return 0;
    }

    // Don't forget to update ScreentoolOptions#validate when changing options
    auto helpInfo = getopt(args,
            std.getopt.config.caseSensitive,
            "s|slop",             "Select an area with the cursor",                   &options.slop,
            "W|capture-window",   "Capture the currently active window",              &options.captureWindow,
            "S|capture-screen",   "Capture the screen containing the active window",  &options.captureScreen,
            "D|capture-desktop",  "Capture the entire desktop (default)",             &options.captureEverything,
            "u|upload",           "Upload image after capture",                       &options.uploadTargets,
            "U|list-uploaders",   "Print available uploaders",                        &options.printUploadTargets,
            "m|minimize-url",     "Use a shortened URL where availible",              &options.shortURL,
            "q|quiet",            "Don't send notifications",                         &options.quiet);

    if (helpInfo.helpWanted)
    {
        writeln("screentool v" ~ "0.1.0" ~ "\n");

        writeln("Options:");

        ulong longestShortOptLength = helpInfo.options.map!( opt => opt.optShort.length ).reduce!((a, b) => max(a, b));
        ulong longestLongOptLength  = helpInfo.options.map!( opt => opt.optLong.length  ).reduce!((a, b) => max(a, b));

        foreach (it; helpInfo.options)
        {
            writefln("  %*s %*-s %s",
                    longestShortOptLength,    it.optShort,
                    longestLongOptLength + 2, it.optLong,
                    it.help);
        }

        return 0;
    }

    string message;
    if (!options.validate(message))
    {
        writeln(message);
        return 1;
    }

    // Stage one: selection

    Geometry geometry;

    if (options.slop)              geometry = selectOperation();
    if (options.captureWindow)     geometry = getActiveWindowGeometry();
    if (options.captureScreen)     geometry = getActiveScreenGeometry();
    if (options.captureEverything) geometry = getDesktopGeometry();

    if (geometry.area <= 0)
    {
        writeln("No valid geometry given.");
        return 1;
    }

    // Stage two: capture

    string filepath = "/tmp/screenshot.png";

    string[] maimCmdline = [ "maim", "-g", geometry.str, filepath ];

    auto maim = execute(maimCmdline);

    if (maim.status != 0)
    {
        write(maim.output);
        return maim.status;
    }

    if (!options.quiet)
        notify("Uploading image..", "");

    // Stage three: post actions

    string url;
    foreach (target; options.uploadTargets) final switch (target)
    {
        case UploadTarget.novaember: url = uploaders.novaember(filepath, options.shortURL); break;
        case UploadTarget.imgur:     url = uploaders.imgur    (filepath, options.shortURL); break;
        case UploadTarget.pomf:      url = uploaders.pomf     (filepath, options.shortURL); break;
    }

    copyToClipboard(url);

    if (!options.quiet)
        notify("Image uploaded!", url);

    return 0;
}

void notify(string header, string bodyStr)
{
     execute([ "notify-send", header, bodyStr ]);
}

void copyToClipboard(string text)
{
    auto xclipPrimary   = pipeProcess([ "xclip", "-selection", "primary"   ], Redirect.stdin);
    auto xclipClipboard = pipeProcess([ "xclip", "-selection", "clipboard" ], Redirect.stdin);

    xclipPrimary.stdin.write(text);
    xclipClipboard.stdin.write(text);
}

auto getScreenGeometries()
{
    auto xrandr = execute([ "xrandr", "--current" ]);

    // Example line: VGA1 connected primary 1920x1200+0+0 (normal left inverted right x axis y axis) 518mm x 324mm
    return xrandr.output.splitLines()
        .filter!(line => line.canFind(" connected ")) // Spaces are important; don't match 'disconnected'
        .map!   (line => Geometry(line)) // Extract geometries
        .filter!(geom => geom.area > 0); // Reject invalid geometries (unused screens)
}

XWindowAttributes getActiveWindow()
{
    Display* display = XOpenDisplay(null);

    Window window;
    int revertTo;
    XGetInputFocus(display, &window, &revertTo);

    XWindowAttributes windowAttributes;
    XGetWindowAttributes(display, window, &windowAttributes);

    return windowAttributes;
}

Geometry selectOperation()
{
    auto slop = execute([ "slop", "--nokeyboard",
            "-c", "1,0.68,0", // border color
            "-b", "1",        // border width
            "-f", "%g",       // custom output format
    ]);

    if (slop.status != 0)
    {
        write(slop.output);
        return *(new Geometry);
    }

    return Geometry(slop.output.chomp);
}

Geometry getActiveWindowGeometry()
{
    auto windowAttributes = getActiveWindow();

    return Geometry(windowAttributes.width, windowAttributes.height, windowAttributes.x, windowAttributes.y);
}

Geometry getActiveScreenGeometry()
{
    auto windowAttributes = getActiveWindow();

    // Find the first screen that contains the center of this window
    int centerX = windowAttributes.x + windowAttributes.width / 2;
    int centerY = windowAttributes.y + windowAttributes.height / 2;

    auto screens = getScreenGeometries();

    return screens.filter!(geom => geom.containsPoint(centerX, centerY)).front;
}

Geometry getDesktopGeometry()
{
    return getScreenGeometries().fold!((a, b) => Geometry(a, b));
}
