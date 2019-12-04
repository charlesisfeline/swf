package;

import swf.exporters.AnimateLibraryExporter;
// import swf.exporters.SWFLiteExporter;
import swf.tags.TagDefineBits;
import swf.tags.TagDefineBitsJPEG2;
import swf.tags.TagDefineBitsJPEG3;
import swf.tags.TagDefineBitsLossless;
import swf.tags.TagDefineButton2;
import swf.tags.TagDefineEditText;
import swf.tags.TagDefineMorphShape;
import swf.tags.TagDefineShape;
import swf.tags.TagDefineSprite;
import swf.tags.TagDefineText;
import swf.tags.TagPlaceObject;
import swf.SWFTimelineContainer;
import swf.SWF;
import haxe.Json;
import haxe.Serializer;
import haxe.Template;
import haxe.Unserializer;
import hxp.*;
import lime.tools.AssetHelper;
import lime.tools.Architecture;
import lime.tools.Asset;
import lime.tools.AssetEncoding;
import lime.tools.AssetType;
import lime.tools.HXProject;
import lime.tools.Platform;
import lime.utils.AssetManifest;
// import swf.exporters.swflite.BitmapSymbol;
// import swf.exporters.swflite.ButtonSymbol;
// import swf.exporters.swflite.DynamicTextSymbol;
// import swf.exporters.swflite.ShapeSymbol;
// import swf.exporters.swflite.SpriteSymbol;
// import swf.exporters.swflite.StaticTextSymbol;
import swf.SWFLibrary;
// import swf.exporters.swflite.SWFLiteLibrary;
// import swf.exporters.swflite.SWFLite;
import openfl.display.PNGEncoderOptions;
import openfl.utils.ByteArray;
import sys.io.File;
import sys.io.Process;
import sys.FileSystem;

using swf.exporters.FrameScriptParser.AVM2;

class Tools
{
	// private static inline var SWFLITE_DATA_SUFFIX = #if force_dat_suffix ".dat" #else ".bin" #end;
	private static var filePrefix:String;
	private static var targetDirectory:String;
	private static var targetFlags:Map<String, String>;

	#if neko
	public static function __init__()
	{
		var haxePath = Sys.getEnv("HAXEPATH");
		var command = (haxePath != null && haxePath != "") ? haxePath + "/haxelib" : "haxelib";
		var path = "";

		var process = new Process("haxelib", ["path", "lime"]);

		try
		{
			while (true)
			{
				var line = StringTools.trim(process.stdout.readLine());

				if (line.length > 0 && !StringTools.startsWith(line, "-"))
				{
					path = StringTools.trim(line);
					if (FileSystem.exists(Path.combine(path, "../lib")))
					{
						path = Path.combine(path, "../lib");
					}
					else
					{
						path = Path.combine(path, "../ndll");
					}
					if (!StringTools.endsWith(path, "/"))
					{
						path += "/";
					}
					break;
				}
			}
		}
		catch (e:Dynamic) {}

		process.close();

		switch (System.hostPlatform)
		{
			case WINDOWS:
				// var is64 = neko.Lib.load("std", "sys_is64", 0)();
				untyped $loader.path = $array(path + "Windows/", $loader.path);
				// if (CFFI.enabled)
				// {
				try
				{
					neko.Lib.load("lime", "lime_application_create", 0);
				}
				catch (e:Dynamic)
				{
					untyped $loader.path = $array(path + "Windows64/", $loader.path);
				}
			// }

			case MAC:
				// untyped $loader.path = $array(path + "Mac/", $loader.path);
				untyped $loader.path = $array(path + "Mac64/", $loader.path);

			case LINUX:
				var arguments = Sys.args();
				var raspberryPi = false;

				for (argument in arguments)
				{
					if (argument == "-rpi") raspberryPi = true;
				}

				if (raspberryPi)
				{
					untyped $loader.path = $array(path + "RPi/", $loader.path);
				}
				else if (System.hostArchitecture == X64)
				{
					untyped $loader.path = $array(path + "Linux64/", $loader.path);
				}
				else
				{
					untyped $loader.path = $array(path + "Linux/", $loader.path);
				}

			default:
		}
	}
	#end

	private static function formatClassName(className:String, prefix:String = null):String
	{
		if (className == null) return null;
		if (prefix == null) prefix = "";

		var lastIndexOfPeriod = className.lastIndexOf(".");

		var packageName = "";
		var name = "";

		if (lastIndexOfPeriod == -1)
		{
			name = prefix + className;
		}
		else
		{
			packageName = className.substr(0, lastIndexOfPeriod);
			name = prefix + className.substr(lastIndexOfPeriod + 1);
		}

		packageName = packageName.charAt(0).toLowerCase() + packageName.substr(1);
		name = name.substr(0, 1).toUpperCase() + name.substr(1);

		if (packageName != "")
		{
			return StringTools.trim(packageName + "." + name);
		}
		else
		{
			return StringTools.trim(name);
		}
	}

	private static function generateSWFClasses(project:HXProject, output:HXProject, swfAsset:Asset, prefix:String = ""):Array<String>
	{
		var bitmapDataTemplate = File.getContent(Haxelib.getPath(new Haxelib("swf"), true) + "/templates/swf/BitmapData.mtt");
		var movieClipTemplate = File.getContent(Haxelib.getPath(new Haxelib("swf"), true) + "/templates/swf/MovieClip.mtt");
		var simpleButtonTemplate = File.getContent(Haxelib.getPath(new Haxelib("swf"), true) + "/templates/swf/SimpleButton.mtt");

		var swf = new SWF(ByteArray.fromBytes(File.getBytes(swfAsset.sourcePath)));

		if (prefix != "" && prefix != null)
		{
			prefix = prefix.substr(0, 1).toUpperCase() + prefix.substr(1);
		}

		var generatedClasses = [];

		var classLookupMap = new Map<Int, String>();
		for (className in swf.symbols.keys())
		{
			classLookupMap.set(swf.symbols[className], className);
		}

		for (className in swf.symbols.keys())
		{
			if (className == null) continue;
			var lastIndexOfPeriod = className.lastIndexOf(".");

			var packageName = "";
			var name = "";

			if (lastIndexOfPeriod == -1)
			{
				name = className;
			}
			else
			{
				packageName = className.substr(0, lastIndexOfPeriod);
				name = className.substr(lastIndexOfPeriod + 1);
			}

			packageName = packageName.charAt(0).toLowerCase() + packageName.substr(1);
			name = formatClassName(name, prefix);

			var symbolID = swf.symbols.get(className);
			var templateData = null;
			var symbol = swf.data.getCharacter(symbolID);
			var baseClassName = null;

			if (Std.is(symbol, TagDefineBits) || Std.is(symbol, TagDefineBitsJPEG2) || Std.is(symbol, TagDefineBitsLossless))
			{
				templateData = bitmapDataTemplate;
				baseClassName = "openfl.display.BitmapData";
			}
			else if (Std.is(symbol, TagDefineButton2))
			{
				templateData = simpleButtonTemplate;
				baseClassName = "openfl.display.SimpleButton";
			}
			else if (Std.is(symbol, SWFTimelineContainer))
			{
				templateData = movieClipTemplate;
				baseClassName = "openfl.display.MovieClip";
			}

			var classData = swf.data.abcData.findClassByName(className);
			if (classData != null)
			{
				if (classData.superclass != null)
				{
					var superClassData = swf.data.abcData.resolveMultiNameByIndex(classData.superclass);
					switch (superClassData.nameSpace)
					{
						case NPublic(_) if (!~/^flash\./.match(superClassData.nameSpaceName)):
							baseClassName = ("" == superClassData.nameSpaceName ? "" : superClassData.nameSpaceName + ".") + superClassData.name;
						case _:
					}
				}
			}

			if (templateData != null)
			{
				var classProperties = [];
				var objectReferences = new Map<String, Bool>();

				if (Std.is(symbol, SWFTimelineContainer))
				{
					var timelineContainer:SWFTimelineContainer = cast symbol;

					if (timelineContainer.frames.length > 0)
					{
						for (frame in timelineContainer.frames)
						{
							for (frameObject in frame.objects)
							{
								var placeObject:TagPlaceObject = cast timelineContainer.tags[frameObject.placedAtIndex];

								if (placeObject != null
									&& placeObject.instanceName != null
									&& !objectReferences.exists(placeObject.instanceName))
								{
									var id = frameObject.characterId;
									var childSymbol = timelineContainer.getCharacter(id);
									var className = null;

									if (classLookupMap.exists(id))
									{
										className = classLookupMap.get(id);
									}
									if (childSymbol != null)
									{
										if (className == null)
										{
											if (Std.is(childSymbol, TagDefineSprite))
											{
												className = "openfl.display.MovieClip";
											}
											else if (Std.is(childSymbol, TagDefineBits)
												|| Std.is(childSymbol, TagDefineBitsJPEG2)
												|| Std.is(childSymbol, TagDefineBitsLossless))
											{
												className = "openfl.display.BitmapData";
											}
											else if (Std.is(childSymbol, TagDefineShape) || Std.is(childSymbol, TagDefineMorphShape))
											{
												className = "openfl.display.Shape";
											}
											else if (Std.is(childSymbol, TagDefineText) || Std.is(childSymbol, TagDefineEditText))
											{
												className = "openfl.text.TextField";
											}
											else if (Std.is(childSymbol, TagDefineButton2))
											{
												className = "openfl.display.SimpleButton";
											}
										}
										else
										{
											className = formatClassName(className, prefix);
										}

										if (className != null && !objectReferences.exists(placeObject.instanceName))
										{
											objectReferences[placeObject.instanceName] = true;
											classProperties.push({name: placeObject.instanceName, type: className});
										}
									}
								}
							}
						}
					}
				}

				var context = {
					PACKAGE_NAME: packageName,
					NATIVE_CLASS_NAME: StringTools.trim(className),
					CLASS_NAME: name,
					BASE_CLASS_NAME: baseClassName,
					SWF_ID: swfAsset.id,
					SYMBOL_ID: symbolID,
					PREFIX: "",
					CLASS_PROPERTIES: classProperties
				};
				var template = new Template(templateData);
				var targetPath;

				// if (project.target == IOS) {

				// 	targetPath = PathHelper.tryFullPath (targetDirectory) + "/" + project.app.file + "/" + "/haxe/_generated";

				// } else {

				targetPath = "../haxe/_generated";

				// }

				var templateFile = new Asset("", Path.combine(targetPath, Path.directory(className.split(".").join("/"))) + "/" + prefix + name + ".hx",
					AssetType.TEMPLATE);
				templateFile.data = template.execute(context);
				output.assets.push(templateFile);

				generatedClasses.push((packageName.length > 0 ? packageName + "." : "") + name);
			}
		}

		return generatedClasses;
	}

	// private static function generateSWFLiteClasses(targetPath:String, output:Array<Asset>, swfLite:SWFLite, swfID:String, prefix:String = ""):Array<String>
	// {
	// 	#if commonjs
	// 	var bitmapDataTemplate = File.getContent(Path.combine(js.Node.__dirname, "../assets/templates/swf/BitmapData.mtt"));
	// 	var movieClipTemplate = File.getContent(Path.combine(js.Node.__dirname, "../assets/templates/swf/MovieClip.mtt"));
	// 	var simpleButtonTemplate = File.getContent(Path.combine(js.Node.__dirname, "../assets/templates/swf/SimpleButton.mtt"));
	// 	#else
	// 	var bitmapDataTemplate = File.getContent(Haxelib.getPath(new Haxelib("openfl"), true) + "/assets/templates/swf/BitmapData.mtt");
	// 	var movieClipTemplate = File.getContent(Haxelib.getPath(new Haxelib("openfl"), true) + "/assets/templates/swf/MovieClip.mtt");
	// 	var simpleButtonTemplate = File.getContent(Haxelib.getPath(new Haxelib("openfl"), true) + "/assets/templates/swf/SimpleButton.mtt");
	// 	#end
	// 	var generatedClasses = [];
	// 	for (symbolID in swfLite.symbols.keys())
	// 	{
	// 		var symbol = swfLite.symbols.get(symbolID);
	// 		var templateData = null;
	// 		var baseClassName = null;
	// 		if (Std.is(symbol, BitmapSymbol))
	// 		{
	// 			templateData = bitmapDataTemplate;
	// 			baseClassName = "openfl.display.BitmapData";
	// 		}
	// 		else if (Std.is(symbol, SpriteSymbol))
	// 		{
	// 			templateData = movieClipTemplate;
	// 			if (cast(symbol, SpriteSymbol).baseClassName != null)
	// 			{
	// 				baseClassName = cast(symbol, SpriteSymbol).baseClassName;
	// 			}
	// 			else
	// 			{
	// 				baseClassName = "openfl.display.MovieClip";
	// 			}
	// 		}
	// 		else if (Std.is(symbol, ButtonSymbol))
	// 		{
	// 			templateData = simpleButtonTemplate;
	// 			baseClassName = "openfl.display.SimpleButton";
	// 		}
	// 		if (templateData != null && symbol.className != null)
	// 		{
	// 			var className = symbol.className;
	// 			var name = className;
	// 			var packageName = "";
	// 			var lastIndexOfPeriod = className.lastIndexOf(".");
	// 			if (lastIndexOfPeriod > -1)
	// 			{
	// 				packageName = className.substr(0, lastIndexOfPeriod);
	// 				if (packageName.length > 0)
	// 				{
	// 					packageName = packageName.charAt(0).toLowerCase() + packageName.substr(1);
	// 				}
	// 				name = className.substr(lastIndexOfPeriod + 1);
	// 			}
	// 			// name = formatClassName(name, prefix);
	// 			var classProperties = [];
	// 			var objectReferences = new Map<String, Bool>();
	// 			if (Std.is(symbol, SpriteSymbol))
	// 			{
	// 				var spriteSymbol:SpriteSymbol = cast symbol;
	// 				if (spriteSymbol.frames.length > 0 && Reflect.hasField(spriteSymbol.frames[0], "objects"))
	// 				{
	// 					for (frame in spriteSymbol.frames)
	// 					{
	// 						if (frame.objects != null)
	// 						{
	// 							for (object in frame.objects)
	// 							{
	// 								if (object.name != null && !objectReferences.exists(object.name))
	// 								{
	// 									if (swfLite.symbols.exists(object.symbol))
	// 									{
	// 										var childSymbol = swfLite.symbols.get(object.symbol);
	// 										var className = childSymbol.className;
	// 										if (className == null)
	// 										{
	// 											if (Std.is(childSymbol, SpriteSymbol))
	// 											{
	// 												className = "openfl.display.MovieClip";
	// 											}
	// 											else if (Std.is(childSymbol, TagDefineBits)
	// 												|| Std.is(childSymbol, TagDefineBitsJPEG2)
	// 												|| Std.is(childSymbol, TagDefineBitsLossless))
	// 											{
	// 												className = "openfl.display.BitmapData";
	// 											}
	// 											else if (Std.is(childSymbol, ShapeSymbol))
	// 											{
	// 												className = "openfl.display.Shape";
	// 											}
	// 											else if (Std.is(childSymbol, BitmapSymbol))
	// 											{
	// 												className = "openfl.display.Bitmap";
	// 											}
	// 											else if (Std.is(childSymbol, DynamicTextSymbol) || Std.is(childSymbol, StaticTextSymbol))
	// 											{
	// 												className = "openfl.text.TextField";
	// 											}
	// 											else if (Std.is(childSymbol, ButtonSymbol))
	// 											{
	// 												className = "openfl.display.SimpleButton";
	// 											}
	// 										}
	// 										else
	// 										{
	// 											// className = formatClassName(className, prefix);
	// 										}
	// 										if (className != null)
	// 										{
	// 											objectReferences[object.name] = true;
	// 											classProperties.push({name: object.name, type: className});
	// 										}
	// 									}
	// 								}
	// 							}
	// 						}
	// 					}
	// 				}
	// 			}
	// 			var context = {
	// 				PACKAGE_NAME: packageName,
	// 				NATIVE_CLASS_NAME: className,
	// 				CLASS_NAME: name,
	// 				BASE_CLASS_NAME: baseClassName,
	// 				SWF_ID: swfID,
	// 				SYMBOL_ID: symbolID,
	// 				PREFIX: "",
	// 				CLASS_PROPERTIES: classProperties
	// 			};
	// 			var template = new Template(templateData);
	// 			var templateFile = new Asset("", Path.combine(targetPath, Path.directory(symbol.className.split(".").join("/"))) + "/" + name + ".hx",
	// 				AssetType.TEMPLATE);
	// 			templateFile.data = template.execute(context);
	// 			output.push(templateFile);
	// 			generatedClasses.push((packageName.length > 0 ? packageName + "." : "") + name);
	// 		}
	// 	}
	// 	return generatedClasses;
	// }

	public static function main()
	{
		var arguments = Sys.args();

		#if !nodejs
		if (arguments.length > 0)
		{
			// When the command-line tools are called from haxelib,
			// the last argument is the project directory and the
			// path SWF is the current working directory

			var lastArgument = "";

			for (i in 0...arguments.length)
			{
				lastArgument = arguments.pop();
				if (lastArgument.length > 0) break;
			}

			lastArgument = new Path(lastArgument).toString();

			if (((StringTools.endsWith(lastArgument, "/") && lastArgument != "/") || StringTools.endsWith(lastArgument, "\\"))
				&& !StringTools.endsWith(lastArgument, ":\\"))
			{
				lastArgument = lastArgument.substr(0, lastArgument.length - 1);
			}

			if (FileSystem.exists(lastArgument) && FileSystem.isDirectory(lastArgument))
			{
				Sys.setCwd(lastArgument);
			}
		}
		#else
		// first argument is node executable, second is path to current script file
		arguments.shift();
		arguments.shift();
		#end

		var words = new Array<String>();
		targetFlags = new Map();

		for (argument in arguments)
		{
			if (argument.substr(0, 1) == "-")
			{
				if (argument.substr(1, 1) == "-")
				{
					var equals = argument.indexOf("=");

					if (equals > -1)
					{
						var field = argument.substr(2, equals - 2);
						var argValue = argument.substr(equals + 1);

						switch (field)
						{
							case "prefix":
								filePrefix = argValue;

							case "targetDirectory":
								targetDirectory = argValue;

							default:
						}
					}
				}
				else
				{
					if (argument == "-v" || argument == "-verbose")
					{
						argument = "-verbose";
						Log.verbose = true;
					}

					targetFlags.set(argument.substr(1), "");
				}
			}
			else
			{
				words.push(argument);
			}
		}

		if (words[0] == "process")
		{
			if (words.length == 1)
			{
				Log.error("Incorrect number of arguments for command 'process'");
				return;
			}

			var inputPath = words[1];
			var outputPath = words.length > 2 ? words[2] : null;

			if (words.length == 1 || Path.extension(inputPath) == "swf")
			{
				if (words.length > 3)
				{
					Log.error("Incorrect number of arguments for command 'process'");
					return;
				}

				Log.info("", Log.accentColor + "Running command: PROCESS" + Log.resetColor);
				processFile(inputPath, outputPath, filePrefix);
			}
			else if (words.length > 2)
			{
				try
				{
					var projectData = File.getContent(inputPath);

					var unserializer = new Unserializer(projectData);
					unserializer.setResolver(cast {resolveEnum: Type.resolveEnum, resolveClass: resolveClass});
					var project:HXProject = unserializer.unserialize();

					var output = processLibraries(project);

					if (output != null)
					{
						File.saveContent(outputPath, Serializer.run(output));
					}
				}
				catch (e:Dynamic)
				{
					Log.error(e);
				}
			}
		}
	}

	private static function processFile(sourcePath:String, targetPath:String, prefix:String = null):Bool
	{
		// #if false // TODO: Make default
		if (targetPath == null)
		{
			targetPath = Path.withoutExtension(sourcePath) + ".zip";
		}
		System.mkdir(Path.directory(targetPath));

		var bytes:ByteArray = File.getBytes(sourcePath);
		var swf = new SWF(bytes);
		var exporter = new AnimateLibraryExporter(swf.data, targetPath);

		return true;
		// 		#else
		// 		var bytes:ByteArray = File.getBytes(sourcePath);
		// 		var swf = new SWF(bytes);
		// 		var exporter = new SWFLiteExporter(swf.data);
		// 		var swfLite = exporter.swfLite;

		// 		if (prefix != null && prefix != "")
		// 		{
		// 			for (symbol in swfLite.symbols)
		// 			{
		// 				if (symbol.className != null)
		// 				{
		// 					symbol.className = formatClassName(symbol.className, prefix);
		// 				}
		// 			}
		// 		}

		// 		if (targetPath == null)
		// 		{
		// 			targetPath = Path.withoutExtension(sourcePath) + ".bundle";
		// 		}

		// 		try
		// 		{
		// 			System.removeDirectory(targetPath);
		// 		}
		// 		catch (e:Dynamic) {}

		// 		System.mkdir(targetPath);

		// 		var project = new HXProject();
		// 		var createdDirectory = false;

		// 		for (id in exporter.bitmaps.keys())
		// 		{
		// 			if (!createdDirectory)
		// 			{
		// 				System.mkdir(Path.combine(targetPath, "symbols"));
		// 				createdDirectory = true;
		// 			}

		// 			var type = exporter.bitmapTypes.get(id) == BitmapType.PNG ? "png" : "jpg";
		// 			var symbol:BitmapSymbol = cast swfLite.symbols.get(id);
		// 			symbol.path = "symbols/" + id + "." + type;
		// 			swfLite.symbols.set(id, symbol);

		// 			var asset = new Asset("", symbol.path, AssetType.IMAGE);
		// 			var assetData = exporter.bitmaps.get(id);
		// 			project.assets.push(asset);

		// 			File.saveBytes(Path.combine(targetPath, symbol.path), assetData);

		// 			if (exporter.bitmapTypes.get(id) == BitmapType.JPEG_ALPHA)
		// 			{
		// 				symbol.alpha = "symbols/" + id + "a.png";

		// 				var asset = new Asset("", symbol.alpha, AssetType.IMAGE);
		// 				var assetData = exporter.bitmapAlpha.get(id);
		// 				project.assets.push(asset);

		// 				File.saveBytes(Path.combine(targetPath, symbol.alpha), assetData);
		// 			}
		// 		}

		// 		createdDirectory = false;
		// 		for (id in exporter.sounds.keys())
		// 		{
		// 			if (!createdDirectory)
		// 			{
		// 				System.mkdir(Path.combine(targetPath, "sounds"));
		// 				createdDirectory = true;
		// 			}

		// 			var symbolClassName = exporter.soundSymbolClassNames.get(id);
		// 			var typeId = exporter.soundTypes.get(id);

		// 			Log.info("", " - \x1b[1mExporting sound:\x1b[0m [id=" + id + ", type=" + typeId + ", symbolClassName=" + symbolClassName + "]");

		// 			var type;
		// 			switch (typeId)
		// 			{
		// 				case SoundType.MP3:
		// 					type = "mp3";
		// 				case SoundType.ADPCM:
		// 					type = "adpcm";
		// 				case _:
		// 					throw "unsupported sound type " + id + ", type " + typeId + ", symbol class name " + symbolClassName;
		// 			};
		// 			var path = "sounds/" + symbolClassName + "." + type;
		// 			var assetData = exporter.sounds.get(id);

		// 			File.saveBytes(Path.combine(targetPath, path), assetData);

		// 			// NOTICE: everything must be .mp3 in its final form, even though we write out various formats to disk
		// 			var soundAsset = new Asset("", "sounds/" + symbolClassName + ".mp3", AssetType.SOUND);
		// 			project.assets.push(soundAsset);
		// 		}

		// 		var swfLiteAsset = new Asset("", "swflite" + SWFLITE_DATA_SUFFIX, AssetType.TEXT);
		// 		var swfLiteAssetData = swfLite.serialize();
		// 		project.assets.push(swfLiteAsset);

		// 		File.saveContent(Path.combine(targetPath, swfLiteAsset.targetPath), swfLiteAssetData);

		// 		var srcPath = Path.combine(targetPath, "src");
		// 		var exportedClasses = [];

		// 		// TODO: Allow prefix, fix generated class SWFLite references
		// 		var prefix = "";
		// 		var uuid = StringTools.generateUUID(20);

		// 		#if !commonjs
		// 		generateSWFLiteClasses(srcPath, exportedClasses, swfLite, uuid, prefix);

		// 		for (file in exportedClasses)
		// 		{
		// 			System.mkdir(Path.directory(file.targetPath));
		// 			File.saveContent(file.targetPath, file.data);
		// 		}
		// 		#end

		// 		var data = AssetHelper.createManifest(project);
		// 		data.libraryType = "swf.exporters.swflite.SWFLiteLibrary";
		// 		data.libraryArgs = ["swflite" + SWFLITE_DATA_SUFFIX, uuid];
		// 		data.name = Path.withoutDirectory(Path.withoutExtension(sourcePath));

		// 		File.saveContent(Path.combine(targetPath, "library.json"), data.serialize());

		// 		var includeXML = '<?xml version="1.0" encoding="utf-8"?>
		// <library>

		// 	<source path="src" />

		// </library>';

		// 		File.saveContent(Path.combine(targetPath, "include.xml"), includeXML);

		// 		return true;
		// 		#end
	}

	private static function processLibraries(project:HXProject):HXProject
	{
		// HXProject._command = project.command;
		HXProject._debug = project.debug;
		HXProject._environment = project.environment;
		HXProject._target = project.target;
		HXProject._targetFlags = project.targetFlags;
		HXProject._templatePaths = project.templatePaths;
		HXProject._userDefines = project.defines;

		var output = new HXProject();
		var embeddedSWF = false;
		var embeddedSWFLite = false;
		var embeddedAnimate = false;
		// var filterClasses = [];

		for (library in project.libraries)
		{
			if (library.sourcePath == null) continue;

			var type = library.type;

			if (type == null)
			{
				type = Path.extension(library.sourcePath).toLowerCase();
			}

			if (type == "swf" && (project.target == Platform.FLASH || project.target == Platform.AIR))
			{
				if (!FileSystem.exists(library.sourcePath))
				{
					Log.warn("Could not find library file: " + library.sourcePath);
					continue;
				}

				Log.info("", " - \x1b[1mProcessing library:\x1b[0m " + library.sourcePath + " [SWF]");

				var swf = new Asset(library.sourcePath, library.name + ".swf", AssetType.BINARY);
				// swf.library = library.name;

				var embed = (library.embed != false);
				// var embed = (library.embed == true); // default to non-embedded

				if (embed)
				{
					// swf.embed = true;
					// output.assets.push (swf);
					// output.haxeflags.push ("-swf-lib " + swf.sourcePath);
					output.haxeflags.push("-resource " + swf.sourcePath + "@swf:" + swf.id);
				}
				else
				{
					swf.embed = false;
					output.assets.push(swf);
				}

				var data = AssetHelper.createManifest(output, library.name);
				data.libraryType = "swf.SWFLibrary";
				data.libraryArgs = [library.name + ".swf"];
				data.name = library.name;
				data.rootPath = "lib/" + library.name;

				swf.library = library.name;

				var asset = new Asset("", "lib/" + library.name + ".json", AssetType.MANIFEST);
				asset.id = "libraries/" + library.name + ".json";
				asset.library = library.name;
				asset.data = data.serialize();
				asset.embed = true;

				output.assets.push(asset);

				if (true || library.generate)
				{
					var generatedClasses = generateSWFClasses(project, output, swf, library.prefix);

					for (className in generatedClasses)
					{
						output.haxeflags.push(className);
					}
				}

				embeddedSWF = true;
				// project.haxelibs.push (new Haxelib ("swf"));
				// output.assets.push (new Asset (library.sourcePath, "libraries/" + library.name + ".swf", AssetType.BINARY));))
			}
			// #if !nodejs
			else if (type == "animate" || type == "swf" || type == "swflite" || type == "swf_lite")
			{
				if (!FileSystem.exists(library.sourcePath))
				{
					Log.warn("Could not find library file: " + library.sourcePath);
					continue;
				}

				Log.info("", " - \x1b[1mProcessing library:\x1b[0m " + library.sourcePath + " [SWF]");

				var cacheAvailable = false;
				var cacheDirectory = null;
				var cacheFile = null;

				if (targetDirectory != null)
				{
					cacheDirectory = targetDirectory + "/obj/libraries";
					cacheFile = cacheDirectory + "/" + library.name + ".zip";

					if (FileSystem.exists(cacheFile))
					{
						var cacheDate = FileSystem.stat(cacheFile).mtime;
						var toolDate = FileSystem.stat(Haxelib.getPath(new Haxelib("openfl"), true) + "/scripts/tools.n").mtime;
						var sourceDate = FileSystem.stat(library.sourcePath).mtime;

						if (sourceDate.getTime() < cacheDate.getTime() && toolDate.getTime() < cacheDate.getTime())
						{
							cacheAvailable = true;
						}
					}

					if (!cacheAvailable)
					{
						if (cacheDirectory != null)
						{
							System.mkdir(cacheDirectory);
						}

						var bytes:ByteArray = File.getBytes(library.sourcePath);
						var swf = new SWF(bytes);
						var exporter = new AnimateLibraryExporter(swf.data, cacheFile);

						if (true || library.generate)
						{
							var targetPath;

							if (project.target == IOS)
							{
								targetPath = Path.tryFullPath(targetDirectory) + "/" + project.app.file + "/" + "/haxe/_generated";
							}
							else
							{
								targetPath = Path.tryFullPath(targetDirectory) + "/haxe/_generated";
							}

							var generatedClasses = exporter.generateClasses(targetPath, output.assets, library.prefix);

							// for (className in generatedClasses)
							// {
							// 	output.haxeflags.push(className);
							// }

							// if (cacheDirectory != null)
							// {
							// 	File.saveContent(cacheDirectory + "/classNames.txt", generatedClasses.join("\n"));
							// }
						}
					}
					else
					{
						// var generatedClasses = File.getContent(cacheDirectory + "/classNames.txt").split("\n");

						// for (className in generatedClasses)
						// {
						// 	output.haxeflags.push(className);
						// }
					}

					var asset = new Asset(cacheFile, "lib/" + library.name + ".zip", AssetType.BUNDLE);
					asset.library = library.name;
					// This causes problems with the Flash target (embedding a ZIP... use a different method?)
					// if (library.embed != null)
					// {
					// 	asset.embed = library.embed;
					// }
					asset.embed = false;
					output.assets.push(asset);

					embeddedAnimate = true;
				}
			}
			// 	else
			// 	#end
			// 	if (type == "swf" || type == "swf_lite" || type == "swflite")
			// 	{
			// 		if (project.target == Platform.FLASH || project.target == Platform.AIR)
			// 		{
			// 			if (!FileSystem.exists(library.sourcePath))
			// 			{
			// 				Log.warn("Could not find library file: " + library.sourcePath);
			// 				continue;
			// 			}

			// 			Log.info("", " - \x1b[1mProcessing library:\x1b[0m " + library.sourcePath + " [SWF]");

			// 			var swf = new Asset(library.sourcePath, library.name + ".swf", AssetType.BINARY);
			// 			// swf.library = library.name;

			// 			var embed = (library.embed != false);
			// 			// var embed = (library.embed == true); // default to non-embedded

			// 			if (embed)
			// 			{
			// 				// swf.embed = true;
			// 				// output.assets.push (swf);
			// 				// output.haxeflags.push ("-swf-lib " + swf.sourcePath);
			// 				output.haxeflags.push("-resource " + swf.sourcePath + "@swf:" + swf.id);
			// 			}
			// 			else
			// 			{
			// 				swf.embed = false;
			// 				output.assets.push(swf);
			// 			}

			// 			var data = AssetHelper.createManifest(output, library.name);
			// 			data.libraryType = "swf.SWFLibrary";
			// 			data.libraryArgs = [library.name + ".swf"];
			// 			data.name = library.name;
			// 			data.rootPath = "lib/" + library.name;

			// 			swf.library = library.name;

			// 			var asset = new Asset("", "lib/" + library.name + ".json", AssetType.MANIFEST);
			// 			asset.id = "libraries/" + library.name + ".json";
			// 			asset.library = library.name;
			// 			asset.data = data.serialize();
			// 			asset.embed = true;

			// 			output.assets.push(asset);

			// 			if (true || library.generate)
			// 			{
			// 				var generatedClasses = generateSWFClasses(project, output, swf, library.prefix);

			// 				for (className in generatedClasses)
			// 				{
			// 					output.haxeflags.push(className);
			// 				}
			// 			}

			// 			embeddedSWF = true;
			// 			// project.haxelibs.push (new Haxelib ("swf"));
			// 			// output.assets.push (new Asset (library.sourcePath, "libraries/" + library.name + ".swf", AssetType.BINARY));
			// 		}
			// 		else
			// 		{
			// 			if (!FileSystem.exists(library.sourcePath))
			// 			{
			// 				Log.warn("Could not find library file: " + library.sourcePath);
			// 				continue;
			// 			}

			// 			Log.info("", " - \x1b[1mProcessing library:\x1b[0m " + library.sourcePath + " [SWF]");

			// 			// project.haxelibs.push (new Haxelib ("swf"));

			// 			var uuid = null;

			// 			var cacheAvailable = false;
			// 			var cacheDirectory = null;
			// 			var merge = new HXProject();

			// 			if (targetDirectory != null)
			// 			{
			// 				cacheDirectory = targetDirectory + "/obj/libraries/" + library.name;
			// 				var cacheFile = cacheDirectory + "/" + library.name + SWFLITE_DATA_SUFFIX;

			// 				if (FileSystem.exists(cacheFile))
			// 				{
			// 					var cacheDate = FileSystem.stat(cacheFile).mtime;
			// 					var swfToolDate = FileSystem.stat(Haxelib.getPath(new Haxelib("openfl"), true) + "/scripts/tools.n").mtime;
			// 					var sourceDate = FileSystem.stat(library.sourcePath).mtime;

			// 					if (sourceDate.getTime() < cacheDate.getTime() && swfToolDate.getTime() < cacheDate.getTime())
			// 					{
			// 						cacheAvailable = true;
			// 					}
			// 				}
			// 			}

			// 			if (cacheAvailable)
			// 			{
			// 				for (file in FileSystem.readDirectory(cacheDirectory))
			// 				{
			// 					if (Path.extension(file) == "png" || Path.extension(file) == "jpg")
			// 					{
			// 						var asset = new Asset(cacheDirectory + "/" + file, file, AssetType.IMAGE);

			// 						if (library.embed != null)
			// 						{
			// 							asset.embed = library.embed;
			// 						}

			// 						merge.assets.push(asset);
			// 					}
			// 				}

			// 				var swfLiteAsset = new Asset(cacheDirectory + "/" + library.name + SWFLITE_DATA_SUFFIX, library.name + SWFLITE_DATA_SUFFIX,
			// 					AssetType.TEXT);

			// 				if (library.embed != null)
			// 				{
			// 					swfLiteAsset.embed = library.embed;
			// 				}

			// 				merge.assets.push(swfLiteAsset);

			// 				if (FileSystem.exists(cacheDirectory + "/classNames.txt"))
			// 				{
			// 					var generatedClasses = File.getContent(cacheDirectory + "/classNames.txt").split("\n");

			// 					for (className in generatedClasses)
			// 					{
			// 						output.haxeflags.push(className);
			// 					}
			// 				}

			// 				if (FileSystem.exists(cacheDirectory + "/uuid.txt"))
			// 				{
			// 					uuid = File.getContent(cacheDirectory + "/uuid.txt");
			// 				}

			// 				embeddedSWFLite = true;
			// 			}
			// 			else
			// 			{
			// 				if (uuid == null)
			// 				{
			// 					uuid = StringTools.generateUUID(20);
			// 				}

			// 				if (cacheDirectory != null)
			// 				{
			// 					System.mkdir(cacheDirectory);
			// 				}

			// 				var bytes:ByteArray = File.getBytes(library.sourcePath);
			// 				var swf = new SWF(bytes);
			// 				var exporter = new SWFLiteExporter(swf.data);
			// 				var swfLite = exporter.swfLite;

			// 				if (library.prefix != null && library.prefix != "")
			// 				{
			// 					var prefix = library.prefix;

			// 					for (symbol in swfLite.symbols)
			// 					{
			// 						if (symbol.className != null)
			// 						{
			// 							symbol.className = formatClassName(symbol.className, prefix);
			// 						}
			// 					}
			// 				}

			// 				for (id in exporter.bitmaps.keys())
			// 				{
			// 					var type = exporter.bitmapTypes.get(id) == BitmapType.PNG ? "png" : "jpg";
			// 					var symbol:BitmapSymbol = cast swfLite.symbols.get(id);
			// 					symbol.path = id + "." + type;
			// 					swfLite.symbols.set(id, symbol);

			// 					var asset = new Asset("", symbol.path, AssetType.IMAGE);
			// 					var assetData = exporter.bitmaps.get(id);

			// 					if (cacheDirectory != null)
			// 					{
			// 						asset.sourcePath = cacheDirectory + "/" + id + "." + type;
			// 						asset.format = type;
			// 						File.saveBytes(asset.sourcePath, assetData);
			// 					}
			// 					else
			// 					{
			// 						asset.data = StringTools.base64Encode(cast assetData);
			// 						// asset.data = bitmapData.encode ("png");
			// 						asset.encoding = AssetEncoding.BASE64;
			// 					}

			// 					if (library.embed != null)
			// 					{
			// 						asset.embed = library.embed;
			// 					}

			// 					merge.assets.push(asset);

			// 					if (exporter.bitmapTypes.get(id) == BitmapType.JPEG_ALPHA)
			// 					{
			// 						symbol.alpha = id + "a.png";

			// 						var asset = new Asset("", symbol.alpha, AssetType.IMAGE);
			// 						var assetData = exporter.bitmapAlpha.get(id);

			// 						if (cacheDirectory != null)
			// 						{
			// 							asset.sourcePath = cacheDirectory + "/" + id + "a.png";
			// 							asset.format = "png";
			// 							File.saveBytes(asset.sourcePath, assetData);
			// 						}
			// 						else
			// 						{
			// 							asset.data = StringTools.base64Encode(cast assetData);
			// 							// asset.data = bitmapData.encode ("png");
			// 							asset.encoding = AssetEncoding.BASE64;
			// 						}

			// 						asset.embed = false;

			// 						if (library.embed != null)
			// 						{
			// 							asset.embed = library.embed;
			// 						}

			// 						merge.assets.push(asset);
			// 					}
			// 				}

			// 				// for (filterClass in exporter.filterClasses.keys ()) {

			// 				// filterClasses.remove (filterClass);
			// 				// filterClasses.push (filterClass);

			// 				// }

			// 				var swfLiteAsset = new Asset("", library.name + SWFLITE_DATA_SUFFIX, AssetType.TEXT);
			// 				var swfLiteAssetData = swfLite.serialize();

			// 				if (cacheDirectory != null)
			// 				{
			// 					swfLiteAsset.sourcePath = cacheDirectory + "/" + library.name + SWFLITE_DATA_SUFFIX;
			// 					File.saveContent(swfLiteAsset.sourcePath, swfLiteAssetData);
			// 				}
			// 				else
			// 				{
			// 					swfLiteAsset.data = swfLiteAssetData;
			// 				}

			// 				if (library.embed != null)
			// 				{
			// 					swfLiteAsset.embed = library.embed;
			// 				}

			// 				merge.assets.push(swfLiteAsset);

			// 				if (library.generate)
			// 				{
			// 					var targetPath;

			// 					if (project.target == IOS)
			// 					{
			// 						targetPath = Path.tryFullPath(targetDirectory) + "/" + project.app.file + "/" + "/haxe/_generated";
			// 					}
			// 					else
			// 					{
			// 						targetPath = Path.tryFullPath(targetDirectory) + "/haxe/_generated";
			// 					}

			// 					var generatedClasses = generateSWFLiteClasses(targetPath, output.assets, swfLite, uuid, library.prefix);

			// 					for (className in generatedClasses)
			// 					{
			// 						output.haxeflags.push(className);
			// 					}

			// 					if (cacheDirectory != null)
			// 					{
			// 						File.saveContent(cacheDirectory + "/classNames.txt", generatedClasses.join("\n"));
			// 					}
			// 				}

			// 				if (cacheDirectory != null)
			// 				{
			// 					File.saveContent(cacheDirectory + "/uuid.txt", uuid);
			// 				}

			// 				embeddedSWFLite = true;
			// 			}

			// 			var data = AssetHelper.createManifest(merge);
			// 			data.libraryType = "swf.exporters.swflite.SWFLiteLibrary";
			// 			data.libraryArgs = [library.name + SWFLITE_DATA_SUFFIX, uuid];
			// 			data.name = library.name;

			// 			if (library.embed == true || (library.embed == null && (project.platformType == WEB || project.target == AIR)))
			// 			{
			// 				data.rootPath = "lib/" + library.name;
			// 			}
			// 			else
			// 			{
			// 				data.rootPath = library.name;
			// 			}

			// 			for (asset in merge.assets)
			// 			{
			// 				asset.library = library.name;
			// 				asset.targetPath = "lib/" + library.name + "/" + asset.targetPath;
			// 				asset.resourceName = asset.targetPath;
			// 			}

			// 			output.merge(merge);

			// 			var asset = new Asset("", "lib/" + library.name + ".json", AssetType.MANIFEST);
			// 			asset.id = "libraries/" + library.name + ".json";
			// 			asset.library = library.name;
			// 			asset.data = data.serialize();

			// 			if (library.embed != null)
			// 			{
			// 				asset.embed = library.embed;
			// 			}

			// 			output.assets.push(asset);
			// 		}
			// 	}
		}

		if (embeddedAnimate)
		{
			output.haxeflags.push("swf.exporters.animate.AnimateLibrary");
		}

		if (embeddedSWF)
		{
			output.haxeflags.push("swf.SWFLibrary");
		}

		if (embeddedSWFLite)
		{
			output.haxeflags.push("swf.exporters.swflite.SWFLiteLibrary");
		}

		if (embeddedSWF || embeddedSWFLite || embeddedAnimate)
		{
			output.haxelibs.push(new Haxelib("swf"));

			var generatedPath;

			if (project.target == IOS)
			{
				generatedPath = Path.combine(targetDirectory, project.app.file + "/" + "/haxe/_generated");
			}
			else
			{
				generatedPath = Path.combine(targetDirectory, "haxe/_generated");
			}

			output.sources.push(generatedPath);

			// add sources and haxelibs again, so that we can
			// prepend the generated class path, to allow
			// overrides if the class is defined elsewhere

			output.sources = output.sources.concat(project.sources);
			output.haxelibs = output.haxelibs.concat(project.haxelibs);

			return output;
		}

		return null;
	}

	private static function resolveClass(name:String):Class<Dynamic>
	{
		var result = Type.resolveClass(name);

		if (result == null)
		{
			result = HXProject;
		}

		return result;
	}
}
