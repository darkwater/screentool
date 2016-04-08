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

struct ScreentoolOptions
{
    Selector selector;
    UploadTarget[] uploadTargets;
}

struct Geometry
{
    uint width, height;
    int x, y;

    static Geometry opCall(string str)
    {
        auto match = str.matchFirst(regex(r"(\d+)x(\d+)\+(\d+)\+(\d+)"));

        Geometry g;
        g.width = match[1].to!uint;
        g.height = match[2].to!uint;
        g.x = match[3].to!int;
        g.y = match[4].to!int;
        return g;
    }

    bool containsPoint(int x, int y)
    {
        return ( x > this.x && y > this.y
              && x < this.x + this.width
              && y < this.y + this.height );
    }

    string str()
    {
        return format("%dx%d%+d%+d", width, height, x, y);
    }
}

ScreentoolOptions options;

int main(string[] args)
{
    auto helpInformation = getopt(args,
            "s|selector", "Method to use for selection", &options.selector,
            "u|upload",   "Upload image after capture",  &options.uploadTargets);


    // Stage one: selection

    string geometry;

    final switch (options.selector)
    {
        case Selector.area:   geometry = select_area();   break;
        case Selector.window: geometry = select_window(); break;
        case Selector.screen: geometry = select_screen(); break;
        case Selector.full:   geometry = select_full();   break;
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


    // Stage three: uploads

    foreach (target; options.uploadTargets) final switch (target)
    {
        case UploadTarget.novaember: uploaders.novaember(filepath).copyToClipboard(); break;
        case UploadTarget.imgur:     uploaders.imgur    (filepath).copyToClipboard(); break;
        case UploadTarget.pomf:      uploaders.pomf     (filepath).copyToClipboard(); break;
    }

    return 0;
}

void copyToClipboard(string text)
{
    auto xclipPrimary   = pipeProcess([ "xclip", "-selection", "primary"   ], Redirect.stdin);
    auto xclipClipboard = pipeProcess([ "xclip", "-selection", "clipboard" ], Redirect.stdin);

    xclipPrimary.stdin.write(text);
    xclipClipboard.stdin.write(text);
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

string select_area()
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

string select_window()
{
    auto windowAttributes = getActiveWindow();

    return format("%dx%d%+d%+d",
            windowAttributes.width,
            windowAttributes.height,
            windowAttributes.x,
            windowAttributes.y);
}

string select_screen()
{
    auto windowAttributes = getActiveWindow();

    // Find the first screen that contains the center of this window
    int centerX = windowAttributes.x + windowAttributes.width / 2;
    int centerY = windowAttributes.y + windowAttributes.height / 2;

    auto xrandr = execute([ "xrandr", "--current" ]);

    // Example line: VGA1 connected primary 1920x1200+0+0 (normal left inverted right x axis y axis) 518mm x 324mm
    auto screens = xrandr.output.splitLines()
        .filter!(line => line.canFind(" connected ")) // Spaces are important; don't match 'disconnected'
        .map!(line => Geometry(line)); // Extract geometries

    Geometry screen = screens.filter!(geom => geom.containsPoint(centerX, centerY)).front;

    return screen.str;
}

string select_full()
{
    return "200x100+50+50";
}
