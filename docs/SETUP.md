# INSTALLATION

Input This To Download.
```
haxelib git hscript-iris-improved https://github.com/NovaFlare-Engine-Concentration/hscript-iris-improved
```

Once this is done, go to your Project File, whether that be a build.hxml for Haxe Projects, or Project.xml for OpenFL and Flixel projects, and add `hscript-iris-improved` to your libraries

---

# SETUP IN HAXE PROJECTS

### Haxe Project Example
```hxml
--library hscript-iris-improved
# this is optional and can be added if wanted
# provides descriptive traces and better error handling at runtime
-D hscriptPos
```

### OpenFL / Flixel Project Example

```xml
<haxelib name="hscript-iris-improved"/>
<haxedef name="hscriptPos"/>
```