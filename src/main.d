module screentool;

import std.conv: text;
import std.file: read;
import std.format: format, formattedRead;
import std.process: environment, execute, pipeProcess, Redirect;
import std.string: chomp;

import std.getopt;
import std.json;
import std.stdio;

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

    int centerX = windowAttributes.x + windowAttributes.width / 2;
    int centerY = windowAttributes.y + windowAttributes.height / 2;

    return format("%dx%d%+d%+d",
            windowAttributes.width,
            windowAttributes.height,
            0, 0);
}

string select_full()
{
    return "200x100+50+50";
}
