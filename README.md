# ExifMeta Plugin for Adobe Lightroom
A snapshot of Rob Cole's ExifMeta plugin for Adobe Lightroom. This is version 5.9 released in
January 2015. I have heard of a 5.10 or 5.11 but I don't have those. Please contact me if you do
and I'd be glad to merge those updates here.

To decrease the size of the GitHub repo, and to avoid any licensing issues I don't know about, I have
not included the Mac or Windows binaries for exiftool here. You may need to acquire those on your own
and put them where they used to be: inside the ExifMeta.lrdevplugin directory.

Rob's web site is no longer online but the "Original ExifMeta Description" below is taken from the 
ExifMeta page on the archive of his site located here:
http://web.archive.org/web/20150215161119/http://www.robcole.com/Rob/ProductsAndServices/ExifMetaLrPlugin/

I am posting this here after a discussion on the Lightroom SDK forum: https://forums.adobe.com/thread/2266047

## Contributing
If you would like to suggest changes or make modifications, feel free to send a pull request for this repo.

## Authors
- **Rob Cole**: [archived site](http://web.archive.org/web/20150210010310/http://www.robcole.com/Rob/index.cfm) 

## License
Rob's license seemed most akin to the MIT license from what I can tell. 
See one example of his [terms and conditions here](http://web.archive.org/web/20150208092405/http://www.robcole.com/Rob/_common/DownloadEasy/Download.cfm?dir=ConfidentialInformantLrPlugin&file=rc_ConfidentialInformant_(lrplugin)_1.4.1.zip)
If you use his code, it'd be a nice tribute to give him some credit somewhere in your project.

# Original ExifMeta Description:
## ExifMeta Lightroom Plugin - Windows + Mac

Reads all exif and camera-specific metadata from source photo files for presentation in right-hand
library panel, library filtering, and smart collection definition.

and/or

Write any exif metadata info - e.g. to update capture time and/or correct missing or lost tags...

Note: ExifMeta comes with exiftool built-in, for both platforms (Windows & Mac) However, you can also
configure exif-meta to use a different copy of exiftool, e.g. as downloaded from Phil Harvey's
website: www.sno.phy.queensu.ca/~phil/exiftool.

## Featuring:

- Harnesses the power of Phil Harvey's ExifTool to bring all your photo metadata to Lightroom.
- Configurable metadata inclusion - take as much or as little as you like.
- Raw file handling - harvest raw metadata only, or xmp too...
- Metadata configurator includes the ability to search, sort, filter, and hide uninteresting metadata.
- Works great with DevMeta - presently the only way to get structured DevMeta info display in the Library
(right)side-panel.
- Works great with NxToo - presently the only way to display NX2 generated metadata in Lightroom,
including all NX2 edit adjustments.
- Write exif metadata including capture time with auto-increment of seconds. Fast - uses session/batch
mode of exif-tool for doing multiple photos (exiftool stays open for the duration...).
- Use built-in exiftool (both platforms), or configure your own.

## System Requirements:

- Lightroom 5, 4, or 3 (not compatible with Lightroom 2)
- Runs on both platforms: Windows & Mac.

### *** See the readme file after downloading for installation instructions and other notes.

## Introducing ExifMeta...

ExifMeta uses exiftool to extract exif (and other) metadata from source files, and uses it to populate 
custom (plugin) metadata in Lightroom, for viewing in Library panel, or filtering in Library module, or 
specifying as criteria in smart collections.

ExifMeta will not modify your source files when doing an update. (there is a separate form you can use 
for explicitly modifying your source files, if that *is* what you want to do).

ExifMeta also acts as the tagset definer for all my (RC) plugins that have custom (plugin) metadata.

## Definitions (for the purposes of ExifMeta)
- **Photo**: Any image in the Lightroom catalog database, excluding videos, regardless of whether its a 
photograph in the strictest sense of the term, or not. Although every photo has a source file associated 
with it, for the purposes of ExifMeta, generally "photo" means "as represented by the Lightroom catalog 
database", as opposed to meaning "source file".

- **Custom (Plugin) Metadata**: There are two kinds of Lightroom metadata:
    1. Native
    2. Custom (Plugin)

    Native is independent of any plugins you may have installed, custom is only available if corresponding
    plugin is installed, has metadata fields defined (and populated), and is enabled.

- **Update**: The act of assuring ExifMeta's custom (plugin) metadata is up to date. Updates are initiated
manually via the file menu, or automatically by virtue of auto-update settings in plugin manager. If no
fields have been defined and committed, then no ExifMeta metadata will be present in Lightroom, even after
a successful "update".

- **Commit**: The act of committing changes to ExifMeta's metadata or tagset field definitions. After
committing changes, all photos will be ripe for an update. However, the actual updating must be initiated
manually via the file menu, unless one is satsified with the auto-updating option performance as enabled
in plugin manager.

- **Tagset**: From a user point of view, its the items in the dropdown list in the Lightroom metadata panel,
to the left of the 'Metadata' section title.

     It defines which metadata is visible in the Metadata section.

    From a programming perspective, tagsets (custom ones that are not included with Lightroom natively)
    are defined by plugins. A tagset must define all items to be displayed. Thus, each plugin can not
    simply add their items to an existing tagset, nor can the user define tagsets to select cross-sections
    of custom metadata from various plugins. Because of this, and because I want the metadata of all my
    plugins plus Lightroom metadata as a single tagset, and because ExifMeta's metadata definitions are not
    pre-defined, ExifMeta was a shoe-in for defining the "all-encompassing" tagset(s).

    (not to be confused with metadata presets, which are for assigning the information contained in metadata
    presets to selected photo(s).

- **Exif Metadata**: Generally means: all metadata in source files. But sometimes is restricted to those 
items having the 'EXIF' tag prefix. See exiftool documentation...
  	 

 
## How to Use (see README file for installation instructions)
1. Export a test catalog if you are leary of turning ExifMeta loose on your working catalog(s).
2. Select a "representative sample" of photos and run a manual update (see file menu - plugin extras).
3. Visit the plugin manager and select some fields to include - consider enabling auto-update options too.
4. Click 'Commit'.
5. Run another update.
6. Repeat steps 3-5 to incorporate new items, or retire un-interesting items.

Hint: once you have the fields defined that you want, run ExifMeta on the entire catalog (e.g. overnight).
So, no updating will need be done while you are working the next day(s)...

## How To Ensure Fresh Metadata
Two ways:
1. Always update after import.
2. Enable auto-update options in plugin manager.

Reminder: you must commit some discovered fields in plugin manager before updating will reveal any metadata.

_And, you must run an update to discover new fields!_

## Plugin Manager Configurator

### ExifMeta General Settings
There is only one setting you can set:
- **Number of metadata item rows**: Make this as big as possible but so it still fits your monitor nicely - 
generally 10-15 for small monitors, 20-35 for bigger monitors.

The other two items are outputs:
- **Database last commit change**: Last time you committed new inclusions which resulted in a database change,
i.e. last time the items included on the right library panel changed...
- **New metadata items last update**: ExifMeta now records which items are new when you do an update. I
recommend either filtering for new items, or viewing log file after doing an update that identifies new items.

Recommended use: After setting number of row items, collapse it - the synopsis has everything else...

### ExifMeta Metadata Selection

First row contains buttons for sorting - clicking a sort button will order rows in a prescribed fashion based 
on the data in the corresponding column. Clicking the same button twice doesn't do anything...

First column is for checking which metadata items are to be included in the library panel, library filters, 
and smart collection definitions. Sort button puts included items at the top.

Second column is for which metadata items are the most "interesting", where interest is defined by number of 
distinct values seen. Those with the most distinct values seen are placed at the top.

'Sort by Name' column puts rows in alphabetical order by name.

'Sort by ID' column puts rows in alphabetical order by ID.

Last column is for hiding - check box to hide item. Note: items are not hidden immediately. To hide checked 
items, click the 'Show Hidden' check box once or twice. Sort button puts unhidden items at the top.

### The row just under the table of rows:

First checkbox (leftmost): Used to set or clear include flag for all metadata items being presented (i.e. 
not filtered out or hidden).

'Up' button: Scroll 1 row "up".

'Down' button: Scroll 1 row "down".

'Page Up' button: Scroll 1 page "up".

'Page Down' button: Scroll 1 page "down".

'Hide Boring Tags' button: Tags which have seen no more than 1 distinct value after updating gobs of photos 
can be considered boring. And in fact, one might consider them boring if they've only seen 2 or 3 distinct 
values. This button affords the opportunity to define boring and mark them for hiding in one fell swoop. 
Note: An especially useful thing to do first is to enter a '1', which won't actually hide anything, but will 
log the number of distinct values seen by each metadata item. (New items are excluded, since they haven't 
been given a chance to be boring yet...).

'Scroll-Pos': position of scroll index within the metadata. '1' is considered the top (all the way "up"). 
the / [number] indicates the index of the last item (all the way "down").

The rightmost checkbox is for setting or clearing the hide flag for all metadata items being presented.

### The bottom row:
(from left to right)

'Not' checkbox: inverts the sense of the filter, excluding what would otherwise be included...

Filter Dropdown:
- Include - present only items to be included.
- New - present only items found last update.
- Interesting - present only items that have seen more than the specified number of distinct values.
- Name - present only items whose name contains the specified filter value, or that match it as regex.
- ID - present only items whose ID contains the specified filter value, or that match it as regex.
- No Filter - do not filter any items. What shows depends only on the 'Show Hidden' control.

Filter Value: a text substring used for Name and ID filters - maybe plain text or Lua regular expression.
Also used for number in cae of "Interesting" filter.

'Show Hidden' checkbox: Show hidden or not - can be clicked once or twice for newly hidden items to take effect.

'Commit' button - roll the included metadata items into a metadata definition and compute corresponding 
tagsets. You may have to restart afterward.
 
### Configuration of Tagsets:

A standard feature of the Elare Preset Manager is to have plugin settings backed by a text configuration file. 
In the case of ExifMeta, all tagsets are defined in this Lua configuration backing file. Defining custom tagsets 
is considered "advanced", but is also quite doable if you have some technical aptitude - instructions are in 
the config file itself.

### Exif Write Form

Purpose is to modify photo source file(s) so exif metadata is forever corrected at the source. Primary 
motivation for this feature was to update capture date/time in old jpegs that had lost their metadata, but it 
is a general purpose tool for writing exif metadata via exiftool.

- Modify raw files (checkbox): 	Check 'modify raw files too' if you want to update both xmp sidecars and 
proprietary raws. Leave unchecked to modify xmp only.
- Modify capture time (checkbox): 	Date-time original will be updated as specified.
- Increment seconds (checkbox): 	Only applies if more than one photo is selected. Here's what I do: 
Arrange photos in user order so they are about in the proper relationship, capture-time-wise, then check 
this box. If unchecked, all selected photos will be assigned the same capture time.
- Date/Time fields.: 	24 hour clock.
- Save copy of originals (checkbox): 	Although unchecked by default, I recommend checking this box unless 
you are certain of what you are doing. It allows you to "undo" what you've done, at any time in the future, 
should you have problems. If you never do have problems, then you can delete the saved original copies.
- Restore copy of originals (push button): 	If, in the past, you have run exiftool commands that created a 
saved original (even if not via Exif Write), this will restore your source files from the previously saved 
originals.
- Delete copy of originals (push button): 	If, in the past, you have run exiftool commands that created a 
saved original (even if not via Exif Write), this will delete them. Run this to tidy up once you are convinced 
everything is AOK.
- Additional tags (checkbox): 	Check this to enable the entry of additional tag/value pairs to write.
- (unnamed popup menu): 	Tag/value pairs - presets - defined in advanced settings - plugin manager, preset 
manager section.
- Tag/Value fields: enter tag names, and associated values (if applicable). Omit quotes.
- Test Run (push button): Does everything except modify files - good to test before committing... - be sure 
to review log file after running.
- Modify Photo Files (push button): Commit capture time and/or other tag mods to photo source files, as specified.
- Done: Quit. Note: this is a disguised version of the cancel button - as such: last field edited will not 
be saved if you haven't "tabbed out of it" yet.
- Help: Quick tips and web link.
