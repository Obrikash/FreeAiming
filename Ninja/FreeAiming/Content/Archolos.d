/*
 * Compatibility fix for The Chronicles of Myrtana: Archolos (unofficial, not part of the original Free Aiming patch)
 *
 * Archolos ships its own, modified LeGo 2.7. When a Ninja patch needs LeGo (like Free Aiming), Ninja parses the
 * Toolkit's LeGo 2.9 on top of it, which breaks Archolos in several ways:
 *
 * - LeGo_All of the Toolkit excludes LeGo_Buffs and LeGo_Render. Archolos initializes LeGo with "LeGo_All & ~(...)",
 *   so the buff display and the item renderer are never set up. Archolos then crashes in its achievement checks, when
 *   buffs are applied (fall damage, food, potions) and in the crafting menus (cooking, alchemy, smithing).
 * - The item renderer of LeGo 2.7 works with pointers, the one of the Toolkit with handles. The Archolos crafting menus
 *   use the returned handles as pointers, corrupting memory (freeze when cooking).
 * - The buff display of Archolos only shows buffs with lCBuff.show and creates icons on demand.
 * - The recipe information in the inventory creates a recipe object every frame.
 * - Broken hook events crash the hook controller instead of being skipped.
 *
 * This file restores the behavior that Archolos expects when Archolos is detected. For other mods the overwritten LeGo
 * functions keep the Toolkit behavior, except that buff icons are created on demand and broken hook events are skipped.
 *
 * Optional diagnostics: Set "archolosDiagnostics=1" in the [GFA] section of Gothic.ini to write checkpoints and all
 * engine hooks to FreeAiming_Archolos.log (in the game folder) and to let Ikarus/LeGo messages through to the
 * Archolos log (system/GOTHIC_ERRORLOG.TXT).
 *
 * License: This file is derived from LeGo and Ikarus (as modified in the Ninja Toolkit by Soeren Zapp) and from the
 * scripts of The Chronicles of Myrtana: Archolos (The Chronicles Of Myrtana Team). Like them, it may only be used in
 * non-commercial form according to the terms of the GothicMOD license (see LICENSE-GothicMOD.txt, or
 * http://www.gothic2.de/mod and http://www.piranha-bytes.com/mod). The MIT license of Free Aiming does not apply
 * to this file.
 */

/*
 * Detect The Chronicles of Myrtana: Archolos (by a symbol of its engine extension KmLib)
 */
func int Patch_GFA_IsArcholos() {
    const int state = -1;
    if (state == -1) {
        state = (MEM_FindParserSymbol("KMLIB_GETPROCADDRESS") != -1);
    };
    return state;
};

/*
 * Optional diagnostics, enabled with archolosDiagnostics=1 in the [GFA] section of Gothic.ini
 */
func int Patch_GFA_Archolos_Diagnostics() {
    const int state = -1;
    if (state == -1) {
        state = Hlp_StrCmp(MEM_GetGothOpt("GFA", "archolosDiagnostics"), "1");
    };
    return state;
};

/*
 * Ninja assigns handles created from within a patch to that patch. They would not be saved with the game and are purged
 * on every initialization. Hand all handles from firstHndl on over to the mod, as if LeGo had created them itself.
 */
func void Patch_GFA_Archolos_HandlesToMod(var int firstHndl) {
    var int h;
    if (!_PM_HandleSort_HT) {
        return;
    };
    h = firstHndl;
    while(h <= nextHandle);
        if (_HT_Has(_PM_HandleSort_HT, h)) {
            _HT_Remove(_PM_HandleSort_HT, h);
        };
        h += 1;
    end;
};

/*
 * Archolos extends lCBuff by the member "show". Look it up by name to stay compatible with other mods.
 */
func int Patch_GFA_Archolos_BuffShown(var int bh) {
    const int showOffset = -2; // -2: Not determined yet, -1: lCBuff has no member "show"
    var int symbID;
    var zCPar_Symbol symb;

    if (showOffset == -2) {
        symbID = MEM_FindParserSymbol("LCBUFF.SHOW");
        if (symbID == -1) {
            showOffset = -1;
        } else {
            symb = _^(MEM_GetSymbolByIndex(symbID));
            showOffset = symb.offset;
        };
    };

    if (showOffset < 0) {
        return TRUE; // LeGo default: Display all buffs of the hero
    };
    return MEM_ReadInt(getPtr(bh) + showOffset);
};

/*
 * Return the icon view at a position in the buff list, create it if it does not exist
 */
func int Patch_GFA_Archolos_BuffView(var int index) {
    var int v;
    var int xsize;
    var int firstHndl;

    v = MEM_ReadStatArr(bufflist_views, index);
    if (Hlp_IsValidHandle(v)) {
        return v;
    };

    Print_GetScreenSize();
    xsize = roundf(divf(mkf(BUFF_HEIGHT), Print_Ratio));
    firstHndl = nextHandle+1;
    v = View_Create((100+xsize)*index, BUFF_Y, (100+xsize)*index+xsize, BUFF_Y+BUFF_HEIGHT);
    Patch_GFA_Archolos_HandlesToMod(firstHndl);
    MEM_WriteStatArr(bufflist_views, index, v);
    return v;
};

/*
 * Overwrites LeGo: Create the buff list of the hero (icon views are created on demand)
 */
func void Bufflist_Init() {
    var int firstHndl;
    var int k;

    if (!Buffs_DisplayForHero) {
        return;
    };

    // Forget icons of a previous list, their handle numbers may be stale
    k = 0;
    while(k < BUFFLIST_SIZE);
        MEM_WriteStatArr(bufflist_views, k, 0);
        k += 1;
    end;

    firstHndl = nextHandle+1;
    bufflist_hero = new(zCArray@);
    if (BUFF_FadeOut) {
        FF_ApplyOnceExtGT(_Bufflist_UpdateDurationFade, 0, -1);
    };
    Patch_GFA_Archolos_HandlesToMod(firstHndl);
};

/*
 * Overwrites LeGo: Display a buff of the hero
 */
func void Bufflist_Add(var int bh) {
    var zCArray arr;
    var lCBuff b;
    var int v;

    if (!Hlp_IsValidHandle(bh)) {
        return;
    };
    if (!Patch_GFA_Archolos_BuffShown(bh)) {
        return; // Hidden buff
    };
    if (!Hlp_IsValidHandle(bufflist_hero)) {
        Bufflist_Init();
        if (!Hlp_IsValidHandle(bufflist_hero)) {
            return;
        };
    };
    if (MEM_ArrayIndexOf(getPtr(bufflist_hero), bh) != -1) {
        return; // Already displayed
    };

    arr = get(bufflist_hero);
    if (arr.numInArray >= BUFFLIST_SIZE) {
        return; // No space left on the screen
    };
    MEM_ArrayInsert(getPtr(bufflist_hero), bh);

    v = Patch_GFA_Archolos_BuffView(arr.numInArray-1);
    b = get(bh);
    View_SetTexture(v, b.buffTex);
    View_Open(v);
};

/*
 * Overwrites LeGo: Remove a buff of the hero from the display
 */
func void Bufflist_Remove(var int bh) {
    var zCArray arr;
    var lCBuff b;
    var int index;
    var int last;
    var int lastBuff;
    var int v;

    if (!Hlp_IsValidHandle(bufflist_hero)) {
        return;
    };
    index = MEM_ArrayIndexOf(getPtr(bufflist_hero), bh);
    if (index < 0) {
        return; // Not displayed (e.g. hidden buff)
    };

    arr = get(bufflist_hero);
    last = arr.numInArray-1;

    // Move the last icon into the gap
    if (index != last) {
        lastBuff = MEM_ReadIntArray(arr.array, last);
        MEM_WriteIntArray(arr.array, index, lastBuff);
        if (Hlp_IsValidHandle(lastBuff)) {
            b = get(lastBuff);
            v = MEM_ReadStatArr(bufflist_views, index);
            if (Hlp_IsValidHandle(v)) {
                View_SetTexture(v, b.buffTex);
            } else {
                v = Patch_GFA_Archolos_BuffView(index);
                View_SetTexture(v, b.buffTex);
                View_Open(v);
            };
        };
    };

    if (last < BUFFLIST_SIZE) {
        v = MEM_ReadStatArr(bufflist_views, last);
        if (Hlp_IsValidHandle(v)) {
            View_Close(v);
        };
    };
    arr.numInArray = last;
};

/*
 * Drop list entries of buffs that no longer exist and restore missing icons
 */
func void Patch_GFA_Archolos_RepairBufflist() {
    var zCArray arr;
    var lCBuff b;
    var int i;
    var int bh;
    var int v;
    var int last;
    var int retexture;

    if (!Hlp_IsValidHandle(bufflist_hero)) {
        return;
    };
    arr = get(bufflist_hero);

    i = 0;
    retexture = FALSE;
    while(i < arr.numInArray);
        bh = MEM_ReadIntArray(arr.array, i);
        if (!Hlp_IsValidHandle(bh)) || (i >= BUFFLIST_SIZE) {
            // Remove the entry by moving the last one into its place
            last = arr.numInArray-1;
            if (last < BUFFLIST_SIZE) {
                v = MEM_ReadStatArr(bufflist_views, last);
                if (Hlp_IsValidHandle(v)) {
                    View_Close(v);
                };
            };
            MEM_WriteIntArray(arr.array, i, MEM_ReadIntArray(arr.array, last));
            arr.numInArray = last;
            retexture = TRUE;
        } else {
            b = get(bh);
            v = MEM_ReadStatArr(bufflist_views, i);
            if (!Hlp_IsValidHandle(v)) {
                v = Patch_GFA_Archolos_BuffView(i);
                View_SetTexture(v, b.buffTex);
                View_Open(v);
            } else if (retexture) {
                View_SetTexture(v, b.buffTex);
            };
            retexture = FALSE;
            i += 1;
        };
    end;
};

/*
 * Archolos uses LeGo 2.7, where the item renderer works with pointers: Render items, their views and the render list
 * are pointers. The Toolkit's LeGo replaced it with a version based on handles, which the Archolos crafting menus
 * (cooking, alchemy, smithing) cannot use: The handles they get back are used as pointers. The functions below keep
 * the Toolkit behavior for other mods and restore the pointer-based behavior for Archolos. Like in LeGo 2.7 the render
 * list is kept in a constant, because the Toolkit made _render_list a variable that is saved with the game.
 */
const int Patch_GFA_Archolos_RenderList = 0; // zCList*

func int Patch_GFA_Archolos_RenderListPtr() {
    if (!Patch_GFA_Archolos_RenderList) {
        Patch_GFA_Archolos_RenderList = List_Create(0);
    };
    return Patch_GFA_Archolos_RenderList;
};

/*
 * Overwrites LeGo
 */
func int _Render_Comparator(var int data1, var int data2) {
    var RenderItem itm1;
    var RenderItem itm2;

    if (Patch_GFA_IsArcholos()) {
        itm1 = _^(data1);
        itm2 = _^(data2);
    } else {
        itm1 = get(data1);
        itm2 = get(data2);
    };
    return (itm1.priority > itm2.priority);
};

/*
 * Overwrites LeGo
 */
func int Render_AddItemPrio(var int itemInst, var int x1, var int y1, var int x2, var int y2, var int priority) {
    var int h;
    var int ptr;
    var RenderItem itm;
    var zCList l;

    if (Patch_GFA_IsArcholos()) {
        ptr = create(RenderItem@);
        itm = _^(ptr);
        itm.inst = itemInst;
        itm.view = ViewPtr_Create(x1, y1, x2, y2);
        itm.priority = priority;
        ViewPtr_Open(itm.view);
        itm.itmPtr = Itm_GetPtr(itemInst);
        l = _^(Patch_GFA_Archolos_RenderListPtr());
        if (l.data) {
            List_InsertSorted(Patch_GFA_Archolos_RenderListPtr(), ptr, _Render_Comparator);
        } else {
            l.data = ptr;
        };
        return ptr;
    };

    h = new(RenderItem@);
    itm = get(h);
    itm.inst = itemInst;
    itm.view = View_Create(x1, y1, x2, y2);
    itm.priority = priority;
    View_Open(itm.view);
    itm.itmPtr = Itm_GetPtr(itemInst);
    l = get(_render_list);
    if (l.data) {
        List_InsertSorted(getPtr(_render_list), h, _Render_Comparator);
    } else {
        l.data = h;
    };
    return +h;
};

/*
 * Overwrites LeGo
 */
func int Render_AddViewPrio(var int view, var int priority) {
    var int h;
    var int ptr;
    var RenderItem itm;
    var zCList l;

    if (Patch_GFA_IsArcholos()) {
        ptr = create(RenderItem@);
        itm = _^(ptr);
        itm.inst = 0;
        itm.view = view;
        itm.priority = priority;
        itm.view_open = 1;
        itm.itmPtr = 0;
        l = _^(Patch_GFA_Archolos_RenderListPtr());
        if (l.data) {
            List_InsertSorted(Patch_GFA_Archolos_RenderListPtr(), ptr, _Render_Comparator);
        } else {
            l.data = ptr;
        };
        return ptr;
    };

    h = new(RenderItem@);
    itm = get(h);
    itm.inst = 0;
    itm.view = view;
    itm.priority = priority;
    itm.view_open = 1;
    itm.itmPtr = 0;
    l = get(_render_list);
    if (l.data) {
        List_InsertSorted(getPtr(_render_list), h, _Render_Comparator);
    } else {
        l.data = h;
    };
    return +h;
};

/*
 * Overwrites LeGo
 */
func void Render_OpenView(var int ID) {
    var RenderItem itm;

    if (Patch_GFA_IsArcholos()) {
        itm = _^(ID);
        itm.view_open = 1;
        if (itm.itmPtr) {
            ViewPtr_Open(itm.view);
        };
        return;
    };

    itm = get(ID);
    itm.view_open = 1;
    // Item views are only rendered if they are open
    if (itm.itmPtr) {
        View_Open(itm.view);
    };
};

/*
 * Overwrites LeGo
 */
func void Render_CloseView(var int ID) {
    var RenderItem itm;

    if (Patch_GFA_IsArcholos()) {
        itm = _^(ID);
        itm.view_open = 0;
        if (itm.itmPtr) {
            ViewPtr_Close(itm.view);
        };
        return;
    };

    itm = get(ID);
    itm.view_open = 0;
    // Item views are only rendered if they are open
    if (itm.itmPtr) {
        View_Close(itm.view);
    };
};

/*
 * Overwrites LeGo
 */
func void Render_Remove(var int ID) {
    var RenderItem itm;
    var int offs;

    if (Patch_GFA_IsArcholos()) {
        itm = _^(ID);
        if (itm.view) {
            ViewPtr_Delete(itm.view);
        };
        MEMINT_GetMemHelper();
        Npc_RemoveInvItem(MEM_Helper, itm.inst);
        offs = List_Contains(Patch_GFA_Archolos_RenderListPtr(), ID);
        if (offs > 0) {
            List_Delete(Patch_GFA_Archolos_RenderListPtr(), offs);
        };
        MEM_Free(ID);
        return;
    };

    itm = get(ID);
    if (itm.view) {
        View_Delete(itm.view);
    };
    MEMINT_GetMemHelper();
    Npc_RemoveInvItem(MEM_Helper, itm.inst); // All items of MEM_Helper are currently in use
    List_Delete(getPtr(_render_list), List_Contains(getPtr(_render_list), ID));
    delete(ID);
};

/*
 * Overwrites LeGo
 */
func void _Render_Hook_Sub(var int list) {
    var RenderItem itm;
    var zCList l; l = _^(list);

    if (Patch_GFA_IsArcholos()) {
        if (l.data) {
            itm = _^(l.data);
            if (itm.itmPtr) {
                oCItem_Render(itm.itmPtr, _render_wld, itm.view, floatNULL);
            } else if (itm.view) && (itm.view_open) {
                ViewPtr_Render(itm.view);
            };
        };
        return;
    };

    if (l.data) {
        itm = get(l.data);
        if (itm.itmPtr) {
            SB_New();
            SB("itmPtr: ");
            SBi(itm.itmPtr);
            SB(" WorldPtr: ");
            SBi(_render_wld);
            SB(" ViewHandle: ");
            SBi(itm.view);
            SB(" ViewPtr: ");
            SBi(View_GetPtr(itm.view));
            MEM_Info(SB_ToString());
            SB_Destroy();
            oCItem_Render(itm.itmPtr, _render_wld, View_GetPtr(itm.view), floatNULL);

        } else if ((itm.view_open) && (Hlp_IsValidHandle(itm.view))) {
            View_Render(itm.view);
        };
    };
};

/*
 * Overwrites LeGo
 */
func void _Render_Hook() {
    if (Patch_GFA_IsArcholos()) {
        if (!Patch_GFA_Archolos_RenderList) { return; };
        if (MEM_Game.singleStep) { return; };
        List_ForF(Patch_GFA_Archolos_RenderList, _Render_Hook_Sub);
        return;
    };

    if (!(getPtr(_render_list))) { return; };
    if (MEM_Game.singleStep) { return; };
    List_ForF(getPtr(_render_list), _Render_Hook_Sub);
};

/*
 * Diagnostics: Append a line to FreeAiming_Archolos.log (in the working directory of the game). The file is closed
 * after every line, so the log survives the game being terminated.
 */
func void Patch_GFA_Archolos_Log(var string line) {
    const int crlf = 0;
    var int h;
    var int written;

    if (!Patch_GFA_Archolos_Diagnostics()) {
        return;
    };

    MEM_Info(ConcatStrings("Free Aiming Archolos fix: ", line));

    if (!crlf) {
        crlf = MEM_Alloc(2);
        MEM_WriteByte(crlf, 13);
        MEM_WriteByte(crlf+1, 10);
    };

    // FILE_APPEND_DATA = 4, OPEN_ALWAYS = 4
    h = WIN_CreateFile("FreeAiming_Archolos.log", 4, FILE_SHARE_READ | FILE_SHARE_WRITE, 0, 4, FILE_ATTRIBUTE_NORMAL, 0);
    if (h == -1) || (!h) {
        return;
    };
    WIN_WriteFile(h, STR_toChar(line), STR_Len(line), _@(written), 0);
    WIN_WriteFile(h, crlf, 2, _@(written), 0);
    WIN_CloseHandle(h);
};

/*
 * Symbol lookups for the Archolos recipe information below (by name, to stay compatible with other mods)
 */
func int Patch_GFA_Archolos_MemberOffset(var string name) {
    var int symbID;
    var zCPar_Symbol symb;

    symbID = MEM_FindParserSymbol(name);
    if (symbID == -1) {
        return -1;
    };
    symb = _^(MEM_GetSymbolByIndex(symbID));
    return symb.offset;
};

func int Patch_GFA_Archolos_TalentKnown(var string arrayName, var int index) {
    var int symbID;
    var zCPar_Symbol symb;

    symbID = MEM_FindParserSymbol(arrayName);
    if (symbID == -1) {
        return FALSE;
    };
    symb = _^(MEM_GetSymbolByIndex(symbID));
    if (index < 0) || (index >= (symb.bitfield & zCPar_Symbol_bitfield_ele)) {
        return FALSE;
    };
    return MEM_ReadIntArray(symb.content, index);
};

func string Patch_GFA_Archolos_KnownSuffix() {
    var int symbID;
    var zCPar_Symbol symb;

    symbID = MEM_FindParserSymbol("NAME_RECIPE_KNOWN_SUFFIX");
    if (symbID == -1) {
        return "";
    };
    symb = _^(MEM_GetSymbolByIndex(symbID));
    return MEM_ReadString(symb.content);
};

/*
 * Overwrites Archolos: Recipe information in the inventory, hooked to oCItemContainer::DrawItemInfo. Same behavior as
 * the Archolos version, with checkpoints in the diagnostics log. Differences: The recipe is created once per recipe
 * instead of every frame, and invalid recipe data is skipped instead of used.
 */
func void oCItemContainer__DrawItemInfo_hook() {
    const int symbIsRecipeDoc = -2; // -2: Not resolved yet
    const int offRecipeItem = -1;
    const int offTalentIndex = -1;
    const int lastItmPtr = 0;
    const int lastHp = 0;
    const int recPtr = 0; // C_Recipe*, kept for the recipe in lastHp
    const int frames = 0;
    var int itmPtr;
    var int hp;
    var int recipeItem;
    var int talentIndex;
    var int recItmPtr;
    var int known;
    var int textArrayPtr;
    var int countArrayPtr;
    var int i;
    var int log;
    var C_Item itm;
    var C_Item recItm;
    var zCPar_Symbol symb;

    if (!ESP) {
        return;
    };
    itmPtr = MEM_ReadInt(ESP+4);
    if (!itmPtr) {
        return;
    };

    if (symbIsRecipeDoc == -2) {
        symbIsRecipeDoc = MEM_FindParserSymbol("ISRECIPEDOC");
        offRecipeItem = Patch_GFA_Archolos_MemberOffset("C_RECIPE.RECIPEITEM");
        offTalentIndex = Patch_GFA_Archolos_MemberOffset("C_RECIPE.TALENTARRAYINDEX");
    };
    if (symbIsRecipeDoc == -1) || (offRecipeItem < 0) || (offTalentIndex < 0) {
        return;
    };

    itm = _^(itmPtr);
    MEM_PushInstParam(itm);
    MEM_CallByID(symbIsRecipeDoc);
    if (!MEM_PopIntResult()) {
        return;
    };

    // Log only once per selected item (and a heartbeat while it stays selected)
    hp = itm.hp;
    log = (itmPtr != lastItmPtr);
    if (log) {
        lastItmPtr = itmPtr;
        frames = 0;
        Patch_GFA_Archolos_Log(ConcatStrings(ConcatStrings("Recipe info: ", itm.name),
                                             ConcatStrings(", recipe instance ", IntToString(hp))));
    } else {
        frames += 1;
        if (frames % 600 == 0) {
            Patch_GFA_Archolos_Log(ConcatStrings("Recipe info still shown, frames: ", IntToString(frames)));
        };
    };

    // The item stores the recipe instance in its hp
    if (hp != lastHp) || (!recPtr) {
        if (hp <= 0) || (hp >= currSymbolTableLength) {
            if (log) { Patch_GFA_Archolos_Log("  skipped: recipe instance out of range"); };
            return;
        };
        symb = _^(MEM_GetSymbolByIndex(hp));
        if ((symb.bitfield & zCPar_Symbol_bitfield_type) != zPAR_TYPE_INSTANCE) {
            if (log) { Patch_GFA_Archolos_Log(ConcatStrings("  skipped: not an instance: ", symb.name)); };
            return;
        };
        symb = _PM_ToClass(hp);
        if (!Hlp_StrCmp(symb.name, "C_RECIPE")) {
            if (log) { Patch_GFA_Archolos_Log(ConcatStrings("  skipped: wrong class: ", symb.name)); };
            return;
        };
        if (log) { Patch_GFA_Archolos_Log("  creating recipe"); };
        if (recPtr) {
            MEM_Free(recPtr);
        };
        recPtr = create(hp);
        lastHp = hp;
    };

    recipeItem = MEM_ReadInt(recPtr + offRecipeItem);
    talentIndex = MEM_ReadInt(recPtr + offTalentIndex);
    if (recipeItem <= 0) || (recipeItem >= currSymbolTableLength) {
        if (log) { Patch_GFA_Archolos_Log(ConcatStrings("  skipped: recipe item out of range: ", IntToString(recipeItem))); };
        return;
    };
    if (log) { Patch_GFA_Archolos_Log(ConcatStrings("  getting item ", IntToString(recipeItem))); };
    recItmPtr = Itm_GetPtr(recipeItem);
    if (!recItmPtr) {
        if (log) { Patch_GFA_Archolos_Log("  skipped: no item"); };
        return;
    };
    recItm = _^(recItmPtr);
    if (log) {
        Patch_GFA_Archolos_Log(ConcatStrings("  item: ", recItm.name));
        Patch_GFA_Archolos_Log(ConcatStrings("  item helper valid: ", IntToString(Hlp_IsValidNpc(Item_Helper))));
    };

    textArrayPtr = _@s(itm.text);
    countArrayPtr = _@(itm.count);

    if (Hlp_StrCmp(itm.visual, "KM_recipe_food_01.3DS")) {
        known = Patch_GFA_Archolos_TalentKnown("PLAYER_TALENT_COOKING", talentIndex);
        if (known) {
            itm.description = ConcatStrings(itm.name, Patch_GFA_Archolos_KnownSuffix());
        };
        i = 0;
        while(i < ITM_TEXT_MAX - 1);
            MEM_WriteStringArray(textArrayPtr, i, MEM_ReadStringArray(_@s(recItm.text), i));
            MEM_WriteIntArray(countArrayPtr, i, MEM_ReadIntArray(_@(recItm.count), i));
            i += 1;
        end;
    } else {
        if (Hlp_StrCmp(itm.visual, "KM_recipe_potion_03.3DS"))
        || (Hlp_StrCmp(itm.visual, "KM_recipe_potion_02.3DS"))
        || (Hlp_StrCmp(itm.visual, "KM_recipe_potion_01.3DS")) {
            known = Patch_GFA_Archolos_TalentKnown("PLAYER_TALENT_ALCHEMY", talentIndex);
        } else {
            known = Patch_GFA_Archolos_TalentKnown("PLAYER_TALENT_SMITH", talentIndex);
        };
        if (known) {
            itm.description = ConcatStrings(itm.name, Patch_GFA_Archolos_KnownSuffix());
        };
        i = 0;
        while(i < ITM_TEXT_MAX - 2);
            MEM_WriteStringArray(textArrayPtr, i+1, MEM_ReadStringArray(_@s(recItm.text), i+1));
            MEM_WriteIntArray(countArrayPtr, i+1, MEM_ReadIntArray(_@(recItm.count), i+1));
            i += 1;
        end;
    };

    if (log) { Patch_GFA_Archolos_Log("  done"); };
};

/*
 * Report broken hook events, together with the engine address they are hooked to
 */
const int Patch_GFA_Archolos_HookAddrTarget = 0;
const int Patch_GFA_Archolos_HookAddrResult = 0;

func void Patch_GFA_Archolos_FindHookAddr_Sub(var int key, var int val) {
    if (val == Patch_GFA_Archolos_HookAddrTarget) {
        Patch_GFA_Archolos_HookAddrResult = key;
    };
};

func void Patch_GFA_Archolos_HookProblem(var int evtHAddr, var string problem) {
    const int reports = 0;
    var string msg;

    if (reports >= 30) {
        return;
    };
    reports += 1;

    Patch_GFA_Archolos_HookAddrTarget = evtHAddr;
    Patch_GFA_Archolos_HookAddrResult = 0;
    if (_Hook_htbl) {
        _HT_ForEach(_Hook_htbl, Patch_GFA_Archolos_FindHookAddr_Sub);
    };

    msg = ConcatStrings("Broken hook event ", IntToString(evtHAddr));
    msg = ConcatStrings(msg, " (engine address ");
    msg = ConcatStrings(msg, IntToString(Patch_GFA_Archolos_HookAddrResult));
    msg = ConcatStrings(msg, "): ");
    msg = ConcatStrings(msg, problem);
    MEM_Warn(ConcatStrings("Free Aiming Archolos fix: ", msg));
    Patch_GFA_Archolos_Log(msg);
};

func int Patch_GFA_Archolos_HookEventValid(var int evtHAddr) {
    var zCArray z;
    var string problem;

    if (!evtHAddr) {
        Patch_GFA_Archolos_HookProblem(evtHAddr, "event is NULL");
        return FALSE;
    };
    z = _^(evtHAddr);
    if (z.numInArray < 0) || (z.numInArray > 256) || (z.numInArray > z.numAlloc)
    || ((z.numInArray > 0) && (!z.array)) {
        problem = ConcatStrings("listeners ", IntToString(z.numInArray));
        problem = ConcatStrings(problem, ", allocated ");
        problem = ConcatStrings(problem, IntToString(z.numAlloc));
        problem = ConcatStrings(problem, ", array ");
        problem = ConcatStrings(problem, IntToString(z.array));
        Patch_GFA_Archolos_HookProblem(evtHAddr, problem);
        return FALSE;
    };
    return TRUE;
};

func int Patch_GFA_Archolos_HookListenerValid(var int evtHAddr, var int funcID) {
    var zCPar_Symbol symb;

    if (funcID > 0) && (funcID < currSymbolTableLength) {
        symb = _^(MEM_GetSymbolByIndex(funcID));
        if ((symb.bitfield & zCPar_Symbol_bitfield_type) == zPAR_TYPE_FUNC) {
            return TRUE;
        };
    };
    Patch_GFA_Archolos_HookProblem(evtHAddr, ConcatStrings("invalid listener ", IntToString(funcID)));
    return FALSE;
};

/*
 * Diagnostics: Log all engine hooks with their events
 */
func void Patch_GFA_Archolos_LogHooks_Sub(var int key, var int val) {
    var zCArray z;
    var string msg;

    msg = ConcatStrings("  hook at ", IntToString(key));
    msg = ConcatStrings(msg, ", event ");
    msg = ConcatStrings(msg, IntToString(val));
    if (val) {
        z = _^(val);
        msg = ConcatStrings(msg, ", listeners ");
        msg = ConcatStrings(msg, IntToString(z.numInArray));
    };
    Patch_GFA_Archolos_Log(msg);
};

func void Patch_GFA_Archolos_LogHooks() {
    if (!Patch_GFA_IsArcholos()) || (!_Hook_htbl) || (!Patch_GFA_Archolos_Diagnostics()) {
        return;
    };
    Patch_GFA_Archolos_Log("Engine hooks:");
    _HT_ForEach(_Hook_htbl, Patch_GFA_Archolos_LogHooks_Sub);
};

/*
 * Overwrites LeGo: Hook controller. Identical to the Toolkit version, except that broken events and listeners are
 * skipped (and reported) instead of being used, and the copy of the listeners is freed.
 */
func void _Hook(var int evtHAddr, // ESP-44
                var int _edi,     // ESP-40 // Function parameters in order of popad (reverse order of pushad)
                var int _esi,     // ESP-36
                var int _ebp,     // ESP-32
                var int _esp,     // ESP-28
                var int _ebx,     // ESP-24
                var int _edx,     // ESP-20
                var int _ecx,     // ESP-16
                var int _eax) {   // ESP-12

    // Backup use-instance before anything else. Temporary variable for now, because it's done before locals()
    var int _instBak_temp; _instBak_temp = MEM_GetUseInstance();

    // Local backup for recursive hooks
    locals();

    // Secure register variables locally for recursive hooks
    var int eaxBak; eaxBak = EAX;
    var int ecxBak; ecxBak = ECX;
    var int edxBak; edxBak = EDX;
    var int ebxBak; ebxBak = EBX;
    var int espBak; espBak = ESP;
    var int ebpBak; ebpBak = EBP;
    var int esiBak; esiBak = ESI;
    var int ediBak; ediBak = EDI;

    // Get address of yINSTANCE_HELP by symbol index 0
    const int instHlpAddr = 0;
    if (!instHlpAddr) {
        instHlpAddr = MEM_GetSymbolByIndex(0)+zCParSymbol_offset_offset;
    };

    // Also secure global instances
    var int selfBak;  selfBak  = _@(self);
    var int otherBak; otherBak = _@(other);
    var int itemBak;  itemBak  = _@(item);
    var int iHlpBak;  iHlpBak  = MEM_ReadInt(instHlpAddr);
    var int instBak;  instBak  = _instBak_temp;

    // Update register variables
    EAX = _eax;
    ECX = _ecx;
    EDX = _edx;
    EBX = _ebx;
    ESP = _esp;
    EBP = _ebp;
    ESI = _esi;
    EDI = _edi;

    // Check whether Ikarus is initialized for hooks that happen during level change
    if (!_@(MEM_Parser)) {
        MEM_InitLabels();
        MEM_InitGlobalInst();
    };

    // Iterate over all registered event handler functions
    // Archolos fix: Only use the event if it looks intact
    var int l; l = 0;
    var int a; a = 0;
    if (Patch_GFA_Archolos_HookEventValid(evtHAddr)) {
        var zCArray z; z = _^(evtHAddr);
        l = z.numInArray;
        a = MEM_Alloc(l<<2);
        MEM_Copy(z.array, a, l); // Duplicate to be safe against manipulation during the loop
    };
    var int i; i = 0;
    while(i < l); // Repeat does not work in combination with LeGo_Locals here!
        // Clear data stack in-between function calls
        MEM_Parser.datastack_sptr = 0;

        // Do not overwrite the global instances by default
        HookOverwriteInstances = FALSE;

        // Obtain hooking function
        var int funcID; funcID = MEM_ReadIntArray(a, i);
        // Archolos fix: Skip listeners that are not functions
        if (Patch_GFA_Archolos_HookListenerValid(evtHAddr, funcID)) {
        var zCPar_Symbol fncSymb; fncSymb = _^(MEM_GetSymbolByIndex(funcID));

        // Supply function arguments if expected
        var int stackOffset; stackOffset = 4;
        var int j; j = 0;
        while(j < (fncSymb.bitfield & zCPar_Symbol_bitfield_ele));
            var zCPar_Symbol symb; symb = _^(MEM_GetSymbolByIndex(funcID+1+j));
            var int stackValue; stackValue = MEM_ReadInt(ESP+stackOffset); stackOffset += 4;
            if ((symb.bitfield & zCPar_Symbol_bitfield_type) == zPAR_TYPE_STRING) {
                // Either zString or zString* on stack
                var string str; str = "";
                if (stackValue) {
                    if (stackValue == zString__vtbl) {
                        str = MEM_ReadString(ESP+stackOffset);
                        stackOffset += sizeof_zString-4;
                    } else if (MEM_ReadInt(stackValue) == zString__vtbl) {
                        str = MEM_ReadString(stackValue);
                    };
                };
                MEM_PushStringParam(str);
            } else if ((symb.bitfield & zCPar_Symbol_bitfield_type) == zPAR_TYPE_INSTANCE) {
                // Either symbol index or pointer on stack
                if (stackValue > 0) && (stackValue < currSymbolTableLength) { // Exclude yINSTANCE_HELP
                    var zCPar_Symbol symb2; symb2 = _^(MEM_GetSymbolByIndex(stackValue));
                    if ((symb2.bitfield & zCPar_Symbol_bitfield_type) == zPAR_TYPE_INSTANCE) {
                        stackValue = symb2.offset;
                    };
                };
                symb.offset = stackValue;
                MEM_PushInstParam(funcID+1+j);
            } else {
                // Otherwise push value directly (integer/float/...)
                MEM_PushIntParam(stackValue);
            };
            j += 1;
        end;

        // Call the function
        MEM_CallByID(funcID);

        // Ninja: Make sure the below feature was introduced before the hook function to ensure compatibility
        const int retFeatureID = 0;
        if (!retFeatureID) {
            retFeatureID = MEM_GetSymbolIndex("_HOOK.FNCSYMB");
        };

        // Assign EAX from return value
        if (fncSymb.offset) && (MEM_Parser.datastack_sptr > 0)
        && (retFeatureID < funcID) { // Function has to be newer than (parsed after) this feature
            if (fncSymb.offset == (zPAR_TYPE_INT >> 12)) || (fncSymb.offset == (zPAR_TYPE_FLOAT >> 12)) {
                // Safety checks on stack integrity
                if (MEM_Parser.datastack_sptr >= 2) {
                    var int sPtr; sPtr = MEM_Parser.datastack_sptr; // Stack pointer is constantly changing so copy it
                    var int tok; tok = contentParserAddress + zCParser_datastack_stack_offset + (sPtr-1)*4;
                    if (MEM_ReadInt(tok) == zPAR_TOK_PUSHINT) || (MEM_ReadInt(tok) == zPAR_TOK_PUSHVAR) {
                        // There is indeed a valid return value
                        EAX = MEM_PopIntResult();
                    };
                };
            } else {
                // Strings are not supported, because we would need a unique string for each hook. Who frees the memory?
                // Instances are not supported, because they are ambiguous: Return a pointer or a symbol ID?
                // Since EAX is a 32-bit register, any non-simple data-type should be manually returned as a pointer
                MEM_Error("HOOKENGINE: Only integer/float return values are supported. Return a pointer if necessary.");
                // No need to clean up the stack here
            };
        };

        // Restore global instances in between function calls
        if (!HookOverwriteInstances) {
            MEM_AssignInstSuppressNullWarning = TRUE;
            self  = _^(selfBak);
            other = _^(otherBak);
            item  = _^(itemBak);
            MEM_AssignInstSuppressNullWarning = FALSE;
        };
        MEM_WriteInt(instHlpAddr, iHlpBak);
        MEM_SetUseInstance(instBak);

        // Stack registers should be kept read-only in between function calls
        ESP = _esp; // Stack pointer is read-only
        };

        i += 1;
    end;
    if (a) {
        MEM_Free(a); // Archolos fix: Free the copy of the listeners
    };

    // Update modifiable registers on stack (ESP points to the position before pushad)
    MEM_WriteInt(ESP-40, EDI);
    MEM_WriteInt(ESP-36, ESI);
    MEM_WriteInt(ESP-32, EBP);
    MEM_WriteInt(ESP-24, EBX);
    MEM_WriteInt(ESP-20, EDX);
    MEM_WriteInt(ESP-16, ECX);
    MEM_WriteInt(ESP-12, EAX);

    // Restore register variables for recursive hooks
    EDI = ediBak;
    ESI = esiBak;
    EBP = ebpBak;
    ESP = espBak;
    EBX = ebxBak;
    EDX = edxBak;
    ECX = ecxBak;
    EAX = eaxBak;

    // Just to be safe: restore again at the very end of the function
    MEM_SetUseInstance(instBak);
};

/*
 * Set up the LeGo packages that the Toolkit's LeGo_All silently drops for Archolos
 */
func void Patch_GFA_ArcholosFix() {
    var int firstHndl;
    var zERROR zerr;

    // Only needed for The Chronicles of Myrtana: Archolos
    if (!Patch_GFA_IsArcholos()) {
        return;
    };

    // Buff display (LeGo_Buffs)
    if (!(_LeGo_Flags & LeGo_Buffs)) {
        if (!Hlp_IsValidHandle(bufflist_hero)) {
            Bufflist_Init();
        } else if (BUFF_FadeOut) {
            firstHndl = nextHandle+1;
            FF_ApplyOnceExtGT(_Bufflist_UpdateDurationFade, 0, -1);
            Patch_GFA_Archolos_HandlesToMod(firstHndl);
        };
        Patch_GFA_Archolos_RepairBufflist();
    };

    // Item rendering in menus (LeGo_Render), set up like the LeGo 2.7 of Archolos
    if (!(_LeGo_Flags & LeGo_Render)) {
        _Render_Init(); // Render hook and world, does nothing if already done in this session
        if (Hlp_IsValidHandle(_render_list)) {
            delete(_render_list); // Handle-based list from the first version of this fix
        };
        _render_list = 0;
        Patch_GFA_Archolos_RenderListPtr();
    };

    // Diagnostics: Let warnings, errors and Ikarus/LeGo messages through to the Archolos log (GOTHIC_ERRORLOG.TXT),
    // without error boxes and with stack traces only for errors
    if (Patch_GFA_Archolos_Diagnostics()) {
        zERR_ShowErrorBox = zERR_TYPE_FATAL + 1;
        zERR_PrintStackTrace = zERR_TYPE_FAULT;
        zerr = _^(MEMINT_SwitchExe(8821208, 9103128, 9172664, 9231568)); // zERROR zerr
        if (zerr.filter_level < 0) {
            zerr.filter_level = 0;
        };

        Patch_GFA_Archolos_Log("--- Archolos fix initialized ---");
        Patch_GFA_Archolos_Log(ConcatStrings("LeGo flags: ", IntToString(_LeGo_Flags)));
        Patch_GFA_Archolos_Log(ConcatStrings("Buff list valid: ", IntToString(Hlp_IsValidHandle(bufflist_hero))));
        Patch_GFA_Archolos_Log(ConcatStrings("Render list: ", IntToString(Patch_GFA_Archolos_RenderList)));
    };
};
