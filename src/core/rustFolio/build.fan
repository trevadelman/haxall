#! /usr/bin/env fan
//
// Copyright (c) 2025, Trevor Adelman
// Licensed under the Academic Free License version 3.0
//
// History:
//   13 Feb 2025  Trevor Adelman  Creation
//

using build

**
** Build: rustFolio
**
class Build : BuildPod
{
  new make()
  {
    podName = "rustFolio"
    summary = "Rust-backed Folio implementation"
    meta    = ["org.name":     "SkyFoundry",
               "org.uri":      "https://skyfoundry.com/",
               "proj.name":    "Haxall",
               "proj.uri":     "https://haxall.io/",
               "license.name": "Academic Free License 3.0",
               "vcs.name":     "Git",
               "vcs.uri":      "https://github.com/haxall/haxall",
               ]
    depends = ["sys @{fan.depend}",
               "concurrent @{fan.depend}",
               "haystack @{hx.depend}",
                "xeto @{hx.depend}",
               "folio @{hx.depend}"]
    srcDirs = [`fan/`]
    // index re-enabled at Milestone 2 when commits+reads are functional
    // index   = ["testFolio.impl": "rustFolio::RustFolioTestImpl"]
  }
}
