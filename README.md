# Quality of Life Research

Get more information at the [Mod Portal](https://mods.factorio.com/mods/Aidiakapi/qol_research) or the [Forums](https://forums.factorio.com/viewtopic.php?t=51002).

A highly customizable mod that adds tech trees for various quality of life adjustments, as well as giving you the option to have flat improvements without research.

File overview:

 - `config.lua` Contains all information regarding what categories of improvements are available.
 - `config_ext.lua` Parses all entries in config, and has utility functions to query derived information.
 - `control.lua` The primary logic for applying the modifications to the force throughout gameplay.
 - `data.lua` Generates the technology prototypes from the configuration.
 - `settings.lua` Generates the settings from the configuration.
 - `data_utils.lua` Utilities for generating data and settings.
 - `flua.lua` Function Iterators and Adapters, a library used throughout.
 - `defines/setting_name_formats.lua` Format strings for generating settings.
