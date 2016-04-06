module uploaders;

import std.conv: text;
import std.file: read;
import std.format: formattedRead;
import std.process: environment, execute, pipeProcess, Redirect;
import std.string: chomp;

import std.json;
import std.stdio;

string novaember(string filepath)
{
    // TODO: Optionally read directly from env var
    string secret = read(environment.get("HOME") ~ "/.nvsecret").text.chomp;

    // TODO: Use libcurl
    auto curl = execute([ "curl", "-s", "http://status.novaember.com/image",
            "-F", "file=@" ~ filepath,
            "-F", "secret=" ~ secret ]);

    // TODO: Handle issues
    JSONValue json = parseJSON(curl.output);
    return json["url"].str;
}

string imgur(string filepath) { return "imgur!"; }
string pomf (string filepath) { return "pomf!";  }
