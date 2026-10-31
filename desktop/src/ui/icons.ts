// Symboles SF (noms enregistrés dans les données de l'app Mac) → icônes Lucide.
// Les variantes « .fill » / « .circle » d'un même symbole partagent une icône : on cherche le nom exact,
// puis sans « .fill », puis sans « .circle ». Ajouter ici tout nouveau symbole utilisé.

import type { Component } from "svelte";
import {
  Archive, ArrowDownRight, ArrowDownToLine, ArrowLeftRight, ArrowUpDown, ArrowUpRight, ArrowUpToLine, Banknote,
  Bike, Bitcoin, Book, BriefcaseMedical, CalendarDays, CalendarPlus, Car, ChartLine, ChartPie, Check, ChevronDown,
  ChevronLeft, ChevronRight, ChevronUp, CircleAlert, CircleArrowDown, CircleArrowUp, CircleCheck, CircleDollarSign,
  CircleEllipsis, CircleMinus, CirclePlus, CircleQuestionMark, CircleX, Cloud, CloudOff, Coffee, CopyPlus, CreditCard,
  Download, Droplet, Dumbbell, Equal, Euro, EyeOff, FileSearch, FileSpreadsheet, FileText, Film, Folder, FolderPlus,
  Footprints, Fuel, Gamepad2, Gauge, Gift, GraduationCap, HardDrive, HardDriveDownload, Hash, Heart, House, Inbox, Keyboard,
  Landmark, LayoutGrid, Leaf, Lightbulb, List, ListChecks, ListFilter, Lock, Music, OctagonX, Pause, PawPrint, Pencil,
  Percent, Phone, Pill, Pin, Plane, Play, Plus, RefreshCw, Repeat, Scissors, Search, Settings, Shield, Shirt,
  ShoppingBag, ShoppingCart, Sheet, Sparkles, SquarePen, Star, Stethoscope, Tag, Tags, TrainFront, Trash2,
  TriangleAlert, Tv, Undo2, Eye, Circle, Upload, Users, Utensils, Wifi, Wine, Wrench, X, Zap,
} from "@lucide/svelte";

const map: Record<string, Component> = {
  // Catégories (liste de l'éditeur de catégorie)
  "cart": ShoppingCart, "house": House, "car": Car, "fuelpump": Fuel, "tram": TrainFront, "airplane": Plane,
  "bicycle": Bike, "fork.knife": Utensils, "cup.and.saucer": Coffee, "wineglass": Wine, "gift": Gift, "tshirt": Shirt,
  "bag": ShoppingBag, "heart": Heart, "cross.case": BriefcaseMedical, "pills": Pill, "stethoscope": Stethoscope,
  "dumbbell": Dumbbell, "gamecontroller": Gamepad2, "film": Film, "book": Book, "music.note": Music, "pawprint": PawPrint,
  "leaf": Leaf, "bolt": Zap, "drop": Droplet, "wifi": Wifi, "phone": Phone, "tv": Tv, "creditcard": CreditCard,
  "banknote": Banknote, "building.columns": Landmark, "graduationcap": GraduationCap,
  "figure.and.child.holdinghands": Users, "wrench.and.screwdriver": Wrench, "scissors": Scissors, "sparkles": Sparkles,
  "repeat": Repeat, "arrow.uturn.backward": Undo2, "plus": Plus, "plus.circle": CirclePlus, "ellipsis": CircleEllipsis,
  "questionmark": CircleQuestionMark,
  // Comptes
  "shield": Shield, "chart.line.uptrend.xyaxis": ChartLine, "figure.walk": Footprints, "bitcoinsign": Bitcoin,
  "dollarsign": CircleDollarSign, "eurosign": Euro, "fork.knife.circle": Utensils,
  // Interface
  "square.grid.2x2": LayoutGrid, "list.bullet": List, "gauge.with.dots.needle.50percent": Gauge, "chart.pie": ChartPie,
  "gearshape": Settings, "arrow.left.arrow.right": ArrowLeftRight, "arrow.up.arrow.down": ArrowUpDown,
  "arrow.down.right": ArrowDownRight, "arrow.up.right": ArrowUpRight, "arrow.down.to.line": ArrowDownToLine,
  "arrow.up.to.line": ArrowUpToLine, "arrow.down": CircleArrowDown, "arrow.up": CircleArrowUp,
  "arrow.triangle.2.circlepath": RefreshCw, "arrow.triangle.2.circlepath.icloud": Cloud, "icloud": Cloud,
  "xmark.icloud": CloudOff, "calendar": CalendarDays, "calendar.badge.plus": CalendarPlus, "checkmark": Check,
  "checkmark.circle": CircleCheck, "checklist": ListChecks, "chevron.down": ChevronDown, "chevron.left": ChevronLeft,
  "chevron.right": ChevronRight, "chevron.up": ChevronUp, "minus": CircleMinus, "equal": Equal,
  "exclamationmark": CircleAlert, "exclamationmark.triangle": TriangleAlert, "xmark.octagon": OctagonX,
  "xmark": X, "xmark.circle": CircleX, "eye.slash": EyeOff, "lightbulb": Lightbulb, "lock": Lock,
  "magnifyingglass": Search, "line.3.horizontal.decrease": ListFilter, "number": Hash, "percent": Percent,
  "pencil": Pencil, "square.and.pencil": SquarePen, "pin": Pin, "pause": Pause, "play": Play,
  "plus.square.on.square": CopyPlus, "square.and.arrow.down": Download, "square.and.arrow.up": Upload,
  "square.and.arrow.down.on.square": Download, "star": Star, "tablecells": Sheet, "file.xlsx": FileSpreadsheet,
  "doc.text": FileText, "doc.text.magnifyingglass": FileSearch, "folder": Folder, "folder.badge.plus": FolderPlus,
  "externaldrive": HardDrive, "externaldrive.badge.plus": HardDriveDownload, "archivebox": Archive, "keyboard": Keyboard,
  "eye": Eye, "circle": Circle,
  "tag": Tag, "tag.slash": Tags, "trash": Trash2, "tray": Inbox,
};

/// Icône Lucide d'un nom de symbole SF ; point d'interrogation si inconnu.
export function iconFor(symbol: string): Component {
  let name = symbol;
  for (let i = 0; i < 3; i++) {
    if (map[name]) return map[name];
    if (name.endsWith(".fill")) name = name.slice(0, -5);
    else if (name.endsWith(".circle")) name = name.slice(0, -7);
    else break;
  }
  return map[name] ?? CircleQuestionMark;
}

/// Symboles proposés pour une catégorie (même liste que SettingsCategories.swift).
export const categorySymbols = [
  "cart", "house", "car", "fuelpump", "tram", "airplane", "bicycle", "fork.knife",
  "cup.and.saucer", "wineglass", "gift", "tshirt", "bag", "heart", "cross.case", "pills",
  "stethoscope", "dumbbell", "gamecontroller", "film", "book", "music.note", "pawprint", "leaf",
  "bolt", "drop", "wifi", "phone", "tv", "creditcard", "banknote", "building.columns",
  "graduationcap", "figure.and.child.holdinghands", "wrench.and.screwdriver", "scissors",
  "sparkles", "repeat", "arrow.uturn.backward.circle", "plus.circle", "ellipsis.circle",
];
