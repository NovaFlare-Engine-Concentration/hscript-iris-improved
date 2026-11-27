# FEATURES

- For loop optimizations
- Generic memory optimizations (现已放屁)

- [x] Imports (i.e: `import ClassPackageAndName;`)
- - [x] Import Aliases (i.e: `import ClassPackageAndName as Class Alias;`)

- [x] Finals

- [x] Improved Error Handling
- - [ ] Using Keyword (partial)

- [x] Enums
- - [ ] Abstract Enums

- [x] Typedefs
- - [x] Redirects
- - [x] Class Redirect (automatic imports)

- [x] Null Coalescing Operator (??, ??=)

- [x] Packages

- [x] Regex

- [x] Parent (Used in `Interp.parentInstance`)

- [x] Getter & Setter

- [x] staticModifier

- [x] Classes
  - Script subclasses of `IScriptedClass` retain their fields, accessors, and method overrides when accessed through the Haxe instance. Properties declared by the script subclass take precedence over Haxe parent properties with the same name.
  - Haxe classes implementing `IScriptedClass` keep their declared members and constructor body. Script `super` calls can reach a method overridden by the Haxe class.

- [x] Support importing static functions of class (But its a shit.)

- [x] String Interpolation (It Still has some trouble. If you need to use it. Please Used in `Parser.allowInterpolation`)

- [x] Better Match

# TODO
---

- Support direct input of packaging class(or enum)
