--[[--
    Localization loader for aire.koplugin.
    Loads l10n/<lang>/aire.mo on demand for the active KOReader language.

    KOReader keeps ONE global translation table and GetText.loadMO() merges
    into it, overwriting what is already there and replacing the plural rule
    with the one in the .mo header. So, after loading the plugin's catalog,
    everything KOReader had before is put back: KOReader's own translations and
    plural rule always win, the plugin only adds what is missing.
--]]

local GetText = require("gettext")
local lfs = require("libs/libkoreader-lfs")

local M = {}

-- Shallow copy, one level deeper for plural tables ({ [0] = ..., [1] = ... })
local function snapshot(t)
    local copy = {}
    for k, v in pairs(t or {}) do
        if type(v) == "table" then
            local inner = {}
            for k2, v2 in pairs(v) do inner[k2] = v2 end
            copy[k] = inner
        else
            copy[k] = v
        end
    end
    return copy
end

local function restore(target, before)
    for k, v in pairs(before) do
        if type(v) == "table" then
            local cur = target[k]
            if type(cur) ~= "table" then
                cur = {}
                target[k] = cur
            end
            for k2, v2 in pairs(v) do cur[k2] = v2 end
        else
            target[k] = v
        end
    end
end

function M.load(plugin_dir)
    local lang = GetText.current_lang
    -- Recordado en GetText: este archivo se carga con dofile desde _meta.lua y main.lua
    if not lang or lang == "C" or lang:match("^en_US") or lang == GetText._aire_l10n_lang then
        return
    end
    if not plugin_dir then
        local src = debug.getinfo(1, "S").source
        plugin_dir = src and src:match("^@(.+)[/\\][^/\\]+$")
        if plugin_dir then
            plugin_dir = plugin_dir:gsub("[/\\]core$", "")
        end
    end
    if not plugin_dir then
        return
    end
    local mo = plugin_dir .. "/l10n/" .. lang .. "/aire.mo"
    if lfs.attributes(mo, "mode") ~= "file" then
        local base = lang:match("^([^_]+)_")
        if base then
            mo = plugin_dir .. "/l10n/" .. base .. "/aire.mo"
        end
    end
    if lfs.attributes(mo, "mode") ~= "file" then
        return
    end
    local before_tr = snapshot(GetText.translation)
    local before_ctx = {}
    for ctx, entries in pairs(GetText.context or {}) do
        before_ctx[ctx] = snapshot(entries)
    end
    local before_plural = GetText.getPlural
    GetText.loadMO(mo)
    GetText.getPlural = before_plural
    restore(GetText.translation, before_tr)
    for ctx, entries in pairs(before_ctx) do
        GetText.context[ctx] = GetText.context[ctx] or {}
        restore(GetText.context[ctx], entries)
    end
    GetText._aire_l10n_lang = lang
end

return M
