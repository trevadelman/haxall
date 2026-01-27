#! /usr/bin/env fan
//
// Copyright (c) 2026, Project Haystack
// Licensed under the Academic Free License version 3.0
//
// History:
//   27 Jan 2026  Trevor Adelman  Creation
//

using build

**
** Build: hxRedis
**
class Build : BuildPod
{
  new make()
  {
    podName = "hxRedis"
    summary = "Redis-backed Folio database implementation"
    meta    = ["org.name":     "Project Haystack",
               "org.uri":      "https://project-haystack.org/",
               "proj.name":    "Haxall",
               "proj.uri":     "https://haxall.io/",
               "license.name": "Academic Free License 3.0",
               "vcs.name":     "Git",
               "vcs.uri":      "https://github.com/haxall/haxall"
              ]
    depends = ["sys @{fan.depend}",
               "concurrent @{fan.depend}",
               "util @{fan.depend}",
               "inet @{fan.depend}",
               "xeto @{hx.depend}",
               "haystack @{hx.depend}",
               "folio @{hx.depend}"]
    srcDirs = [`fan/`, `test/`]
    // Python native directory for transpilation
    // pyDirs = [`py/`]
    docApi  = false
    index   = ["testFolio.impl": "hxRedis::HxRedisTestImpl"]
  }
}
