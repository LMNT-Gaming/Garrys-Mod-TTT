// LMNT – Syntaxprüfung aller .lua-Dateien unter dem übergebenen Ordner (Lua 5.1).
// GLua-Erweiterungen (!=, &&, ||, continue, //-Kommentare) sind im LMNT-Code nicht erlaubt,
// damit diese Prüfung greift.
const fs = require("fs");
const path = require("path");
const luaparse = require("luaparse");

const root = path.resolve(process.argv[2] || ".");
let files = 0;
let errors = 0;

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full);
    } else if (entry.name.endsWith(".lua")) {
      files++;
      try {
        luaparse.parse(fs.readFileSync(full, "utf8"), { luaVersion: "5.1" });
      } catch (e) {
        errors++;
        console.log("FEHLER " + path.relative(root, full) + ": " + e.message);
      }
    }
  }
}

walk(root);
console.log(files + " Lua-Dateien geprüft, " + errors + " Fehler");
process.exit(errors ? 1 : 0);
