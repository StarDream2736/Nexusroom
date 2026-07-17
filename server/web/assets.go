package webassets

import "embed"

// FS contains the public NexusRoom pages and their local JavaScript runtime.
//
//go:embed *.html *.js
var FS embed.FS
