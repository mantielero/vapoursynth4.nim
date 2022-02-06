{.passL:"-lvapoursynth".}
{.passC:"-I/usr/include/vapoursynth/" .}

when defined(linux):
  const
    libname* = "libvapoursynth.so"
elif defined(windows):
  const
    libname* = "vapoursynth.dll"
else:
  const
    libname* = "libvapoursynth.dylib"

import strformat, strutils, os, std/unicode
import ../wrapper/vapoursynth_wrapper

import ../lib/constants
import ../lib/vsplugins

## TODO: I use "ptr VSMap" in order to be able to chain functions.
## but it would be better to know the result of invoke, rather than using ptr VSMap as an output always.
#let API = getVapourSynthAPI(4.cint)
#let CORE = API.createCore(0)

#include "../wrapper/vsmap4.nim"
#include "../wrapper/vsplugins4.nim"

let KEYWORDS = @["addr", "and", "as", "asm", "bind", "block", "break", "case", "cast",
"concept", "const", "continue", "converter", "defer", "discard",
"distinct", "div", "do", "elif", "else", "end", "enum", "except", "export",
"finally", "for", "from", "func", "if", "import", "in", "include",
"interface", "is", "isnot", "iterator", "let", "macro", "method", "mixin",
"mod", "nil", "not", "notin", "object", "of", "or", "out", "proc", "ptr",
"raise", "ref", "return", "shl", "shr", "static", "template", "try", 
"tuple", "type", "using", "var", "when", "while", "xor", "yield" ]


let renames = @[ ("bas", @[("Source", "aSource")]) ]

type
  Plugin = tuple[id:string, namespace:string, description:string]
  #Argument = tuple[name:string, `type`:string, optional:bool]
  Function = tuple[name:string, arguments:seq[Argument]]


#let renames = @[("ffms", @[("Source","v")])]

#[ YO CREO QUE YA NO ES NECESARIO
iterator getPlugins():Plugin =
  ## Iterate over all the plugins available in the system
  let plugins:ptr VSMap = API.getPlugins( CORE )
  for item in plugins.items:
    for i in 0..<plugins.len(item): # Each item within a key
      let data = plugins.propGetData(item.key,i)
      let data_items = data.split(';')
      var tmp:Plugin
      tmp.namespace = data_items[0]
      tmp.id = data_items[1]
      tmp.description = data_items[2]
      yield tmp
]#
#[ YO CREO QUE YA NO ES NECESARIO
iterator getFunctions(item:Plugin):Function =
  ## Iterate over all the functions available in the plugin
  let plugin = getPluginById(item.id)
  # Read all functions in the plugin
  let functions:ptr VSMap = getFunctions(plugin)
  for func_item in functions.items:
    for i in 0..<functions.len(func_item):        
      var function:Function
      let func_data = functions.propGetData(func_item.key,i)
      let func_data_items = func_data.split(';')
      let fname = func_data_items[0]
      if func_data_items.len > 1:
        for j in 1..<func_data_items.len:
          let args = func_data_items[j].split(':')
          var argument:Argument
          if args.len >= 2:
            argument.name = args[0]
            argument.`type` = args[1]
            argument.optional = if args.len == 3: true else: false
            function.arguments &= argument

          #echo args

      function.name = fname
      yield function
]#

#[ YO CREO QUE NO ES NECESARIO
func `$`(plugin:Plugin):string =
  result = &"""
Plugin:
  id         : {plugin.id}
  namespace  : {plugin.namespace}
  description: {plugin.description}
"""
]#

#[ YO CREO QUE NO ES NECESARIO 
func `$`(function:Function):string =
  result = &"Function: {function.name}\n"
  for argument in function.arguments:
    let optional = if argument.optional: "OPTIONAL" else: ""
    result &= &"  {argument.name}:{argument.`type`}  {optional}\n"
]#

#[ YO CREO QUE NO ES NECESARIO  
proc showPlugins() =
  for plugin in getPlugins():
    echo plugin
    for function in getFunctions(plugin):
      echo function
]#

proc convertType(`type`:string):string =
  result = case `type`:
           of "int[]":
             "seq[int]"
           of "float[]":
             "seq[float]"
           of "data":
             "string" 
           of "data[]":
             "seq[string]"
           of "vnode":
             #"VNode"
             "ptr VSNode"   
           of "vnode[]":
             "seq[ptr VSNode]"                          
           of "anode":
             "ptr VSNode"   
             #"ANode"
           of "anode[]":
             "seq[ptr VSNode]"  
           of "clip":
             "ptr VSNode"
           of "clip[]":
             "seq[ptr VSNode]"
           of "frame":
             "ptr VSFrame"             
           of "frame[]":
             "seq[ptr VSFrame]"               
           of "func":
             "ptr VSFunction"             
           of "func[]":
             "seq[ptr VSFunction]"             
           else:
             `type`

proc genSignature( function:ptr VSPluginFunction; 
                   rename:seq[tuple[oldName,newName:string]]):string =
  ## creates the function's signature
  
  # Function name:
  # - renames the function to avoid clashes.
  var fname = function.name
  for i in rename:
    if i.oldName == fname:
      fname = i.newName

  # - first letter to lowercase
  fname = fname[0].toLowerAscii & fname[1 .. fname.high]
  result = &"proc {fname}*("
  
  
  var flagFirstArgument = true  # special handling for the first argument 
  for arg in function.args:
    var argName = arg.name
    # If the argument is a Nim keyword, then enclosed between "`" symbol.
    if argName in KEYWORDS: 
      argName = &"`{argName}`"

    # Get the appropriate Nim type from the VapourSynth type
    var newtype = convertType( arg.typ )

    # If not first argument the symbol is added
    if not flagFirstArgument:  
      #if arg.optional: 
        result &= "; "  # Arguments separation
      #else:
      #  result &= ", "        

    # first argument is handled ina a special way
    if arg.typ in ["vnode", "vnode[]", "anode", "anode[]"] and flagFirstArgument:
      argName = "vsmap"
      newtype = "ptr VSMap"

    # Different handling for optional and mandatory arguments
    if not arg.optional: # Mandatory
      result &= &"{argName}:{newtype}"
    else:                # Optional
      result &= &"{argName} = none({newtype})"
    flagFirstArgument = false

  result &= "):ptr VSMap =\n"


proc genBodyForFirstArgument(function:ptr VSPluginFunction):string =
  # For the cases where the first argument is clip, we transform it
  # into a VSMap, to allow chaining calls
  if function.args.len == 0:
    return ""  

  # Get first argument
  result = ""
  let arg = function.args[0]
  var argName = arg.name

  if argName in KEYWORDS: 
    argName = &"`{argName}`"
  let newtype = convertType( arg.typ )

  
  if arg.typ in ["vnode", "vnode[]", "anode", "anode[]"]: # ["clip", "clip[]"]:
    #firstArg &= "\n  let tmpSeq = vsmap.toSeq    # Convert the VSMap into a sequence\n"
    var ident = ""
    var vsmap = "vsmap"
    if arg.optional:
      #if arg.isSome:
        result &= "  if vsmap.isSome:\n"
        ident = "  "
        vsmap = "vsmap.get"
    
    result &= &"  {ident}assert( {vsmap}.len != 0, \"the vsmap should contain at least one item\")\n"                 
    #echo result


    # Just one clip
    var clip = "vnode" # "clip"
    if newtype == "ptr VSNode":
      result &= &"  {ident}assert( {vsmap}.len(\"{clip}\") == 1, \"the vsmap should contain one node\")\n"
      if not arg.optional:  # Mandatory
        result &= &"  var {argName} = getFirstNode(vsmap)\n\n" 
      else:
        #result &= &"  if {argName}.isSome: args.{funcName}(\"{arg.name}\", {argName}.get)\n"
        result &= &"  var {argName}:ptr VSNode\n"
        result &= "  if vsmap.isSome:\n"
        result &= &"    {argName} = getFirstNode(vsmap.get)\n\n"
    
    # For a sequence of clips in the first argument
    # TODO: to extract all nodes in the list and add it to the new map
    elif newtype == "seq[ptr VSNode]":
      clip = "clips"           
      result &= &"  {ident}assert( {vsmap}.len(\"{clip}\") >= 1, \"the vsmap should contain a seq with nodes\")\n"

      if not arg.optional:
        result &= &"  var {argName} = getFirstNodes(vsmap)\n\n"            
      else:
        result &= &"  var {argName}:seq[ptr VSNode]\n"
        result &= &"  if vsmap.isSome:\n"        
        result &= &"    {argName} = getFirstNodes(vsmap.get)\n\n"



proc genBodyForOtherArguments(function:ptr VSPluginFunction; ini=1):string =
  if function.args.len <= 1:
    return ""   

  # Get other arguments
  result = ""
  let args = function.args
  if args.len > 1:
    for arg in args[ini..high(args)]:
      #let arg = function.arguments[0]
      var argName = arg.name
      if argName in KEYWORDS: 
        argName = &"`{argName}`"
      let newtype = convertType( arg.typ )
      let funcName = case newtype:
                     of "seq[int]", "seq[float]":
                       "set"
                     else:
                       "append"
      # If the argument is a sequence
      if newtype[0..2] == "seq" and funcName != "set":
        if not arg.optional:
          result &= &"  for item in {argName}:\n"
          result &= &"    args.{funcName}(\"{arg.name}\", item)\n"     
        else:
          result &= &"  if {argName}.isSome:\n"
          result &= &"    for item in {argName}.get:\n"
          result &= &"      args.{funcName}(\"{arg.name}\", item)\n"  
    
      else: 
        if not arg.optional:
          result &= &"  args.{funcName}(\"{arg.name}\", {argName})\n"     
        else:
          if argName == "clip":
            argName = "vsmap"
            result &= &"  if {argName}.isSome: args.{funcName}(\"{arg.name}\", clip)\n"   # {argName}.get
          else:
            result &= &"  if {argName}.isSome: args.{funcName}(\"{arg.name}\", {argName}.get)\n" 




proc addFirstArgument(function:ptr VSPluginFunction):string =
  if function.args.len == 0:
    return ""
  if not (function.args[0].typ in ["vnode", "vnode[]"]):
    return ""
  let arg = function.args[0]
  var argName = arg.name
  if argName in KEYWORDS: 
    argName = &"`{argName}`"
  var ident = ""

  # If the first argument is optional
  if arg.optional:
    result = "  if vsmap.isSome:\n"
    ident = "  "

  if function.args[0].typ in @["vnode", "anode"]:
    result &= &"  {ident}args.append(\"{arg.name}\", {argName})"
  else:
    result &= &"  {ident}for item in {argName}:\n"
    result &= &"    {ident}args.append(\"{arg.name}\", item)\n"
    #retun tmp #&"  args.append(\"{arg.name}\", {argName})"







proc genFunction(plugin:ptr VSPlugin, function:ptr VSPluginFunction):string =     
  ## Creates a function from a plugin.       

  # Get the arguments
  var rename:seq[tuple[oldName,newName:string]] = @[]
  for item in renames:
    if item[0] == plugin.namespace:
      rename = item[1]
      #echo rename 

  let func_signature = genSignature(function, rename)

  let body_first_argument = genBodyForFirstArgument(function)
  let add_first_argument  = addFirstArgument(function)
  var ini = 1
  if add_first_argument == "":
    ini = 0
  let body_other_arguments = genBodyForOtherArguments(function, ini)    
  result &= &"""
{func_signature}
  let plug = getPluginById("{plugin.id}")
  assert( plug != nil, "plugin \"{plugin.id}\" not installed properly in your computer") 
{body_first_argument}
  # Convert the function parameters into a VSMap (taking into account that some of them might be optional)
  let args = createMap()
{add_first_argument}
{body_other_arguments}
  result = API.invoke(plug, "{function.name}".cstring, args)
  API.freeMap(args)
"""
  

proc main2 =
  for plugin in plugins():
    var source = ""
    for function in functions( plugin ):
    #echo plugin.name, " ", plugin.id, " ", plugin.nameSpace, " ", plugin.path, " ", plugin.version
      var source = genFunction(plugin, function)
      echo "  Function: ", function.name
      echo "    Arguments: ", function.args
      echo "    Ret: ", function.ret


proc main =
  os.createDir("../plugins")  
  var includes = """import options
import ../wrapper/vapoursynth_wrapper
import ../lib/[constants, vsplugins, vsmap]

"""
  for plugin in plugins():
    var source = ""
    for function in functions(plugin):
      source &= genFunction(plugin, function)
      source &= "\n\n"

    let name = &"../plugins/{plugin.namespace}.nim"
    writeFile(name, source)
    echo "[INFO] Written file: ", name
    includes &= &"include {plugin.namespace}\n"

  writeFile("../plugins/all_plugins.nim", includes)
  echo "Written file: ", "../plugins/all_plugins.nim"  

main()