-- HolyOrders — localization
-- The English text is the key; untranslated keys fall through unchanged.

local HO = HolyOrders

local L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
HO.L = L

if GetLocale() ~= "deDE" then
	return
end

-- options
L["HolyOrders — Options"] = "HolyOrders — Optionen"
L["Show cast bar"] = "Buffleiste anzeigen"
L["Open edit: others may change my assignments"] = "Offene Bearbeitung: Andere dürfen meine Zuteilungen ändern"
L["Prefer greater blessings even for single members"] = "Große Segen auch bei einzelnen Mitgliedern bevorzugen"
L["Buff hunter pets"] = "Jäger-Begleiter segnen"
L["Buff warlock pets"] = "Hexenmeister-Begleiter segnen"
L["Show minimap button"] = "Minimap-Button anzeigen"
L["Show status messages in chat"] = "Statusmeldungen im Chat anzeigen"
L["Share assignments with legacy blessing addons"] = "Zuteilungen mit älteren Segens-Addons teilen"
L["Log sync messages (debug)"] = "Sync-Nachrichten protokollieren (Debug)"
L["Keep cast bar above other windows"] = "Leiste über anderen Fenstern halten"
-- dropdown labels
L["Pet blessing"] = "Begleiter-Segen"
L["Bar grows"] = "Leiste wächst"
L["Fly-out opens"] = "Fly-out öffnet"
L["Skin"] = "Skin"
L["Cast bar scale"] = "Leisten-Skalierung"
L["Window scale"] = "Fenster-Skalierung"
L["the new skin applies after a UI reload — reload now?"] = "Der neue Skin greift nach einem UI-Neuladen — jetzt neu laden?"

-- assignment window
L["HolyOrders — Assignments"] = "HolyOrders — Zuteilungen"
L["expand or collapse all classes"] = "alle Klassen auf- oder zuklappen"
L["Save"] = "Speichern"
L["Run the deterministic auto-planner"] = "Deterministischen Auto-Planer ausführen"
L["Force rebuff: refresh everything before the pull"] = "Zwangs-Rebuff: vor dem Pull alles auffrischen"
L["Save the current plan for this paladin roster"] = "Aktuellen Plan für diese Paladin-Besetzung speichern"
L["Encounter toggle: swap Salvation for substitutes, click again to restore the previous plan (lead/assist)"] = "Encounter-Schalter: Rettung durch Ersatz-Segen ersetzen; erneut klicken stellt den vorherigen Plan wieder her (Leiter/Assistent)"
L["click: blessing — right-click: clear — shift-click: mode — click class: members"] = "Klick: Segen — Rechtsklick: leeren — Shift-Klick: Modus — Klick auf Klasse: Mitglieder"
L["mode: |cff40c0ffA|r auto (greater from %d+ members) — |cffffd100G|r always greater (symbol) — |cff40ff40S|r always 10-min singles"] = "Modus: |cff40c0ffA|r auto (Groß ab %d Mitgliedern) — |cffffd100G|r immer Groß (Symbol) — |cff40ff40S|r immer 10-Min-Einzelsegen"
L["no assignment"] = "keine Zuteilung"
L["no blessing assigned"] = "Kein Segen zugewiesen"
L["no blessing assigned — wheel to assign"] = "Kein Segen zugewiesen — mit dem Mausrad zuweisen"
L["click: next blessing — right-click: clear"] = "Klick: nächster Segen — Rechtsklick: leeren"
L["shift-click: change the cast mode"] = "Shift-Klick: Wirkmodus ändern"
L["mode: auto — greater from %d+ members, singles otherwise"] = "Modus: auto — Groß ab %d Mitgliedern, sonst Einzelsegen"
L["with %d member(s) now: %s"] = "mit aktuell %d Mitglied(ern): %s"
L["greater (30 min, whole class, 1 Symbol of Kings)"] = "Groß (30 Min, ganze Klasse, 1 Symbol der Könige)"
L["10-min singles (too few members for greater)"] = "10-Min-Einzelsegen (zu wenige Mitglieder für Groß)"
L["mode: greater — always the Greater Blessing: 30 min, hits the whole class, costs a Symbol of Kings per cast"] = "Modus: Groß — immer der Große Segen: 30 Min, trifft die ganze Klasse, kostet je Wirken ein Symbol der Könige"
L["mode: normal — always 10-min single blessings on each member, no reagent"] = "Modus: normal — immer 10-Min-Einzelsegen auf jedes Mitglied, ohne Reagenz"
L["override by %s: %s"] = "Überschreibung durch %s: %s"
L["inherited from class assignment: %s"] = "geerbt aus Klassen-Zuteilung: %s"
L["remembered preference: %s"] = "Gemerkte Vorliebe: %s"
L["none"] = "keine"
L["(pet of %s)"] = "(Begleiter von %s)"
L["[tank]"] = "[Tank]"
L["%s — all covered"] = "%s — alle versorgt"

-- cast bar
L["left: %s on %s"] = "Links: %s auf %s"
L["right: %s (single)"] = "Rechts: %s (Einzelsegen)"
L["right-click: %s (whole class, 1 Symbol)"] = "Rechtsklick: %s (ganze Klasse, 1 Symbol)"
L["all remaining targets are out of range"] = "alle verbleibenden Ziele sind außer Reichweite"
L["%d out of range (skipped)"] = "%d außer Reichweite (übersprungen)"
L["%d missing"] = "%d fehlen"
L["%d expiring soon"] = "%d laufen bald ab"
-- handle tooltip: "[Gesture] action" lines
L["Left-Click"] = "Linksklick"
L["Right-Click"] = "Rechtsklick"
L["Ctrl-Left-Drag"] = "Strg-Linksklick ziehen"
L["Shift-Right-Click"] = "Shift-Rechtsklick"
L["Open the assignment window"] = "Zuteilungsfenster öffnen"
L["Toggle the force rebuff (pre-pull refresh)"] = "Zwangs-Rebuff umschalten (vor dem Pull)"
L["Move the cast bar"] = "Buffleiste verschieben"
L["Open the options"] = "Optionen öffnen"
L["force rebuff is running — right-click cancels"] = "Zwangs-Rebuff läuft — Rechtsklick bricht ab"
L["mouse wheel: change my assignment"] = "Mausrad: meine Zuteilung wechseln"
L["in combat: click cycles through the class's members"] = "Im Kampf: Klick wirkt reihum auf die Mitglieder der Klasse"

-- cast-bar class fly-out
L["no buff assigned"] = "Kein Segen zugewiesen"
L["has the blessing"] = "hat den Segen"
L["missing the blessing"] = "Segen fehlt"
L["out of range"] = "außer Reichweite"
L["all covered"] = "alles abgedeckt"
L["wheel: change blessing — right-click: clear"] = "Mausrad: Segen wechseln — Rechtsklick: leeren"
L["left-click: cast — wheel: change — right-click: clear"] = "Linksklick: wirken — Mausrad: wechseln — Rechtsklick: leeren"
L["assignment changes apply after combat"] = "Zuteilungsänderungen werden nach dem Kampf übernommen"

-- paladin aura
L["Aura"] = "Aura"
L["My Aura"] = "Meine Aura"
L["no aura assigned"] = "Keine Aura zugewiesen"
L["mouse wheel: change your aura"] = "Mausrad: deine Aura wechseln"
L["aura: %s"] = "Aura: %s"
L["click: next aura — right-click: clear"] = "Klick: nächste Aura — Rechtsklick: leeren"

-- minimap button
L["click: assignment window"] = "Klick: Zuteilungsfenster"
L["click: buff request"] = "Klick: Segenswunsch"
L["right-click: force rebuff"] = "Rechtsklick: Zwangs-Rebuff"
L["shift-click: options"] = "Shift-Klick: Optionen"
L["drag: move this button"] = "Ziehen: Button verschieben"

-- buff requests
L["Buff Request"] = "Segenswunsch"
L["requesting: %s"] = "Wunsch: %s"
L["no request"] = "kein Wunsch"
L["requested: %s"] = "gewünscht: %s"
L["Clear"] = "Leeren"
L["click a blessing to request it for yourself"] = "Klicke einen Segen, um ihn für dich zu erbitten"
L["preferences: %s"] = "Vorlieben: %s"
L["click blessings in priority order — click again to remove"] = "Segen in Prioritätsreihenfolge anklicken — erneut klicken entfernt"

-- frequent chat messages
L["force rebuff cancelled"] = "Zwangs-Rebuff abgebrochen"
L["force rebuff: refreshing everything older than 2 minutes (ends when all fresh)"] = "Zwangs-Rebuff: alles älter als 2 Minuten wird erneuert (endet, wenn alles frisch ist)"
L["force rebuff complete — all assigned buffs are fresh"] = "Zwangs-Rebuff abgeschlossen — alle zugeteilten Segen sind frisch"
L["plan broadcast to the group"] = "Plan an die Gruppe gesendet"
L["plan is local — only your own assignments sync (lead/assist can broadcast all)"] = "Plan ist lokal — nur die eigenen Zuteilungen werden synchronisiert (Leiter/Assistent kann alles senden)"
L["stored plan applied for this paladin roster"] = "Gespeicherter Plan für diese Paladin-Besetzung angewendet"
L["stored plan for this roster available — '/ho plan apply' loads it (your unsaved edits are kept until then)"] = "Gespeicherter Plan für diese Besetzung verfügbar — '/ho plan apply' lädt ihn (ungespeicherte Änderungen bleiben bis dahin erhalten)"
L["only lead/assist may flag others as tank"] = "Nur Leiter/Assistent dürfen andere als Tank markieren"
L["can't move the bar in combat — will reset it after combat"] = "Leiste kann im Kampf nicht bewegt werden — sie wird nach dem Kampf zurückgesetzt"
L["this duty is a single-member override — change it in the assignment window"] = "Diese Aufgabe ist eine Einzelmitglied-Überschreibung — ändere sie im Zuteilungsfenster"
