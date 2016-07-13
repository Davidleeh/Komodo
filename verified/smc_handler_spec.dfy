include "kev_constants.dfy"
include "Maybe.dfy"
include "pagedb.dfy"

datatype smcReturn = Pair(pageDbOut: PageDb, err: int)

// TODO FIXME!!
function mon_vmap(p:PageNr) : int {
    p 
}

function pagedbFrmRet(ret:smcReturn): PageDb
    { match ret case Pair(p,e) => p }

function errFrmRet(ret:smcReturn): int 
    { match ret case Pair(p,e) => e }

function pageIsFree(d:PageDb, pg:PageNr) : bool
    requires pg in d;
    { d[pg].PageDbEntryFree? }


function allocateDispatcherPage(pageDbIn: PageDb, securePage: PageNr,
    addrspacePage:PageNr, entrypoint:int) : smcReturn
    requires validPageDb(pageDbIn)
    requires wellFormedAddrspace(pageDbIn, addrspacePage)
    requires validAddrspace(pageDbIn, addrspacePage)
    // ensures  validPageDb(pagedbFrmRet(allocateDispatcherPage(pageDbIn, securePage, addrspacePage, entrypoint )))
{
    var addrspace := pageDbIn[addrspacePage].entry;
    if(!validPageNr(securePage)) then Pair(pageDbIn, KEV_ERR_INVALID_PAGENO())
    else if(!pageIsFree(pageDbIn, securePage)) then Pair(pageDbIn, KEV_ERR_PAGEINUSE())
    else if(addrspace.state != InitState) then
        Pair(pageDbIn,KEV_ERR_ALREADY_FINAL())
    // Model page clearing for non-data pages?
    else
        var updatedAddrspace := match addrspace
            case Addrspace(l1, ref, state) => Addrspace(l1, ref + 1, state);
        var pageDbUpdated := pageDbIn[
            securePage := PageDbEntryTyped(addrspacePage, Dispatcher(entrypoint, false))];
        var pageDbOut := pageDbUpdated[
            addrspacePage := PageDbEntryTyped(addrspacePage, updatedAddrspace)];
        
        // assert wellFormedPageDb(pageDbOut);
        // assert pageDbEntriesWellTypedAddrspace(pageDbOut);
        // assert validPageDbEntry(pageDbOut, addrspacePage);
        // 
        // //These two fail
        // assert validPageDbEntry(pageDbOut, securePage);
        // assert forall n :: n in pageDbOut && n != addrspacePage && n != securePage ==>
        //     validPageDbEntry(pageDbOut, n);
        // assert pageDbEntriesValid(pageDbOut);

        // assert pageDbEntriesValidRefs(pageDbOut);
        // assert validPageDb(pageDbOut);
        Pair(pageDbOut, KEV_ERR_SUCCESS())
}

function initAddrspace(pageDbIn: PageDb, addrspacePage: PageNr, l1PTPage: PageNr)
    : smcReturn
    requires validPageDb(pageDbIn);
    ensures  validPageDb(pagedbFrmRet(initAddrspace(pageDbIn, addrspacePage, l1PTPage)));
{
    var g := pageDbIn;
    if(!validPageNr(addrspacePage) || !validPageNr(l1PTPage) ||
        addrspacePage == l1PTPage) then
        Pair(pageDbIn, KEV_ERR_INVALID_PAGENO())
    else if(l1PTPage % 4 != 0) then
        Pair(pageDbIn, KEV_ERR_INVALID_PAGENO())
    else if( !g[addrspacePage].PageDbEntryFree? || !g[l1PTPage].PageDbEntryFree? ) then
        Pair(pageDbIn, KEV_ERR_PAGEINUSE())
    else
        var addrspace := Addrspace(l1PTPage, 1, InitState);
        var l1PT := L1PTable(SeqRepeat(NR_L1PTES(),Nothing));
        var pageDbOut := 
            (pageDbIn[addrspacePage := PageDbEntryTyped(addrspacePage, addrspace)])[
                l1PTPage := PageDbEntryTyped(addrspacePage, l1PT)];
        

        // Necessary semi-manual proof of validPageDbEntry(pageDbOut, l1PTPage)
        // The interesting part of the proof deals with the contents of addrspaceRefs
        assert forall p :: p != l1PTPage ==> !(p in addrspaceRefs(pageDbOut, addrspacePage));
		assert l1PTPage in addrspaceRefs(pageDbOut, addrspacePage);
        assert addrspaceRefs(pageDbOut, addrspacePage) == {l1PTPage};
        assert validPageDbEntry(pageDbOut, l1PTPage);


        // begin proof off [pages other than l1PTPage and AddrspacePage are valid]
        ghost var otherPages := set n : PageNr | 0 <= n < KEVLAR_SECURE_NPAGES()
             && n != addrspacePage && n != l1PTPage;

        //Typed page case
        ghost var otherPagesTyped := set n : PageNr | 0 <= n < KEVLAR_SECURE_NPAGES()
             && pageDbOut[n].PageDbEntryTyped?
             && n != addrspacePage && n != l1PTPage;

        assert forall n :: n in otherPages && pageDbOut[n].PageDbEntryTyped? ==>
            pageDbEntryWellTypedAddrspace(pageDbOut, n);
        
        // set of typed pages is preserved 
        assert forall n :: n in otherPages && pageDbIn[n].PageDbEntryTyped? ==> 
            pageDbOut[n].PageDbEntryTyped?;
        assert forall n :: n in otherPages && !(pageDbIn[n].PageDbEntryTyped?) ==> 
            !(pageDbOut[n].PageDbEntryTyped?);


        // addrspace of typed entries is preserved
        assert forall n :: n in otherPagesTyped ==>// && pageDbOut[n].PageDbEntryTyped? ==>
            pageDbOut[n].addrspace == pageDbIn[n].addrspace;

        // entry of typed entries is preserved
        assert forall n :: n in otherPagesTyped ==>// && pageDbOut[n].PageDbEntryTyped? ==>
            pageDbOut[n].entry == pageDbIn[n].entry;


        assert forall n :: n in otherPagesTyped ==>// && pageDbIn[n].PageDbEntryTyped? ==>
            validPageDbEntry(pageDbIn, n);

        // prove validPageDbEntryTyped by cases on type of entry
        
        //Trivial cases
        assert forall n :: n in otherPagesTyped && pageDbOut[n].entry.Dispatcher? ==>
            validPageDbEntryTyped(pageDbOut, n);
        assert forall n :: n in otherPagesTyped && pageDbOut[n].entry.DataPage? ==>
            validPageDbEntryTyped(pageDbOut, n);
        assert forall n :: n in otherPagesTyped && pageDbOut[n].entry.L1PTable? ==>
            validPageDbEntryTyped(pageDbOut, n);
        assert forall n :: n in otherPagesTyped && pageDbOut[n].entry.L2PTable? ==>
            validPageDbEntryTyped(pageDbOut, n);


        // begin proof of [other addrspaces valid]
        ghost var otherAddrspaces := set n : PageNr | 0 <= n < KEVLAR_SECURE_NPAGES()
             && pageDbOut[n].PageDbEntryTyped?
             && pageDbOut[n].entry.Addrspace?
             && n != addrspacePage && n != l1PTPage;
        
        assert forall n :: n in otherAddrspaces  ==>
            wellFormedAddrspace(pageDbOut, n);
       
        // begin proof of [validAddrspace of otherAddrspaces] 
        assert forall n :: n in otherAddrspaces ==>
            validPageNr(pageDbOut[n].entry.l1ptnr);
        assert forall n :: n in otherAddrspaces ==>
            pageDbOut[n].entry.l1ptnr in pageDbOut;
        assert forall n :: n in otherAddrspaces ==>
            pageDbOut[pageDbOut[n].entry.l1ptnr].PageDbEntryTyped?;
        assert forall n :: n in otherAddrspaces ==>
            pageDbOut[pageDbOut[n].entry.l1ptnr].entry.L1PTable?;


        // begin proof of [other addrspace refs ok]
        assert forall n :: n in otherAddrspaces ==>
            addrspaceRefs(pageDbOut, n) == addrspaceRefs(pageDbIn, n);
        assert forall n :: n in otherAddrspaces ==>
            pageDbOut[n].entry.refcount == pageDbIn[n].entry.refcount;

        assert forall n :: n in otherAddrspaces ==>
            pageDbIn[n].entry.refcount == |addrspaceRefs(pageDbIn, n)|;

        // [other addrspace refs ok] needs proof
        assert forall n :: n in otherAddrspaces ==>
            pageDbOut[n].entry.refcount == |addrspaceRefs(pageDbOut, n)|;

        // [validAddrspace of otherAddrspaces] needs manual proof
        assert forall n :: n in otherAddrspaces  ==>
            validAddrspace(pageDbOut, n);
        
        assert forall n :: n in otherAddrspaces  ==>
            validPageDbEntryTyped(pageDbOut, n);

        // [other addrspaces valid]: Only nontrivial case
        assert forall n :: n in otherPagesTyped && pageDbOut[n].entry.Addrspace? ==>
            validPageDbEntryTyped(pageDbOut, n);

        assert forall n :: n in otherPagesTyped ==>// && pageDbOut[n].PageDbEntryTyped? ==>
            validPageDbEntryTyped(pageDbOut, n);

        assert forall n :: n in otherPagesTyped ==>// && pageDbOut[n].PageDbEntryTyped? ==>
            validPageDbEntry(pageDbOut, n);

        assert forall n :: n in otherPagesTyped ==>// && pageDbOut[n].PageDbEntryFree? ==>
            validPageDbEntry(pageDbOut, n);
        
        // Free page case trivial

        // [pages other than l1PTPage and AddrspacePage are valid] needs proof
        assert forall n :: n in otherPages ==> validPageDbEntry(pageDbOut, n);
        assert forall n :: validPageNr(n) && n != addrspacePage && n != l1PTPage ==>
            validPageDbEntry(pageDbOut, n);


        assert pageDbEntriesValid(pageDbOut);

        assert validPageDb(pageDbOut);
        Pair(pageDbOut, KEV_ERR_SUCCESS())
}

// lemma eqEntryEqAddrspace(dIn: PageDb, dOut: PageDb, p: PageNr)
//     requires validPageDb(dIn)
//     requires wellFormedPageDb(dOut)
//     requires validPageNr(p)
//     requires dIn[p] == dOut[p]
//     ensures  dIn[p].PageDbEntryTyped? ==>
//        dIn[p].addrspace == dOut[p].addrspace
// {
// 
// }

function initDispatcher(pageDbIn: PageDb, page:PageNr, addrspacePage:PageNr,
    entrypoint:int)
    : smcReturn
    requires validPageDb(pageDbIn);
    // ensures  validPageDb(pagedbFrmRet(initDispatcher(pageDbIn, page, addrspacePage, entrypoint)));
{
   var n := page;
   var d := pageDbIn;
   if(!wellFormedAddrspace(pageDbIn, addrspacePage) ||
       !validAddrspace(pageDbIn, addrspacePage)) then
       Pair(pageDbIn, KEV_ERR_INVALID_ADDRSPACE())
   else
       allocateDispatcherPage(pageDbIn, page, addrspacePage, entrypoint)
}

// function initL2PTable(pageDbIn: PageDb, page: PageNr, addrspacePage: PageNr, l1Idx:int)
//     : smcReturn
// {
//     if( l1Idx > NR_L1PTES() ) then Pair(KEV_ERR_INVALIDMAPPING(), PageDbIn)
//     if( 
// }

//-----------------------------------------------------------------------------
// Properties of SMC calls
//-----------------------------------------------------------------------------
//  lemma initAddrspaceSuccessValidPageDB(pageDbIn: PageDb, addrspacePage: PageNr, l1PTPage: PageNr)
//      ensures 
//          validPageDb(pagedbFrmRet(initAddrspaceSuccess(pageDbIn, addrspacePage, l1PTPage)))
//  {
//  }