include "entry.s.dfy"
include "ptables.i.dfy"

predicate validSysState'(s:SysState)
{
    validSysState(s) && SaneMem(s.hw.m) && pageDbCorresponds(s.hw.m, s.d)
}

/*
predicate AUCIdef_inner(s:state, r:state)
    requires ValidState(s) 
{
    reveal_ValidRegState();
    SaneMem(s.m) && SaneMem(r.m) &&
    exists ss : SysState :: ss.hw == s && validSysState'(ss)
    && exists rr : SysState :: rr.hw == r && validSysState'(rr) && 
        mode_of_state(ss.hw) != User
    && (rr.hw.regs[R0], rr.hw.regs[R1], rr.d) ==
            exceptionHandled_premium(ss)
}
*/

predicate AUCIdef()
{
    reveal_ValidRegState();
    reveal_ValidSRegState();
    // It needed to be separated out like this to prove 
    // validExceptionTransition
    (forall s:SysState, r:SysState, dp:PageNr | validSysState(s) &&
        validDispatcherPage(s.d, dp) &&
        ApplicationUsermodeContinuationInvariant(s.hw, r.hw) ::
            validExceptionTransition(s, r, dp)) &&
    forall s:SysState, r:SysState, dp:PageNr | validSysState(s) &&
        validDispatcherPage(s.d, dp) &&
        ApplicationUsermodeContinuationInvariant(s.hw, r.hw) ::
            mode_of_state(s.hw) != User &&
            validSysState'(r) &&
            decode_mode'(psr_mask_mode(
                s.hw.sregs[spsr(mode_of_state(s.hw))])) == Just(User) &&
            (r.hw.regs[R0], r.hw.regs[R1], r.d) ==
                exceptionHandled_premium(s.hw, s.d, dp)

}

function exceptionHandled_premium(s:state, d:PageDb, dispPg:PageNr) : (int, int, PageDb)
    requires ValidState(s) && validPageDb(d)
    requires mode_of_state(s) != User
    requires 
        (reveal_ValidSRegState();
        decode_mode'(psr_mask_mode(
        s.sregs[spsr(mode_of_state(s))])) == Just(User))
    requires validDispatcherPage(d, dispPg)
    ensures var (r0,r1,d) := exceptionHandled_premium(s, d, dispPg);
        validPageDb(d)
{
    exceptionHandledValidPageDb(s, d, dispPg);
    exceptionHandled(s, d, dispPg)
}

lemma exceptionHandledValidPageDb(s:state, d:PageDb, dispPg:PageNr)
    requires ValidState(s) && validPageDb(d)
    requires mode_of_state(s) != User
    requires 
        (reveal_ValidSRegState();
        decode_mode'(psr_mask_mode(
        s.sregs[spsr(mode_of_state(s))])) == Just(User))
    requires validDispatcherPage(d, dispPg)
    ensures var (r0,r1,d) := exceptionHandled(s, d, dispPg);
        validPageDb(d)
{
    reveal_validPageDb();
    reveal_ValidSRegState();
    reveal_ValidRegState();
    var (r0,r1,d') := exceptionHandled(s, d, dispPg);

    assert validPageDbEntry(d', dispPg);

    forall( p' | validPageNr(p') && d'[p'].PageDbEntryTyped? && p' != dispPg )
        ensures validPageDbEntry(d', p');
    {
        var e  := d[p'].entry;
        var e' := d'[p'].entry;
        if(e.Addrspace?){
            assert e.refcount == e'.refcount;
            assert addrspaceRefs(d', p') == addrspaceRefs(d,p');
            assert validAddrspace(d',p');
        }
    }

    assert pageDbEntriesValid(d');
    assert validPageDb(d');
}

lemma enterUserspacePreservesPageDb(d:PageDb,s:state,s':state)
    requires SaneMem(s.m) && SaneMem(s'.m) && validPageDb(d)
        && ValidState(s) && ValidState(s')
    requires evalEnterUserspace(s, s')
    requires pageDbCorresponds(s.m, d)
    ensures  pageDbCorresponds(s'.m, d)
{
    reveal_PageDb();
    reveal_ValidMemState();
    reveal_pageDbEntryCorresponds();
    reveal_pageContentsCorresponds();
}

lemma nonWritablePagesAreSafeFromHavoc(m:addr,s:state,s':state)
    requires ValidState(s) && ValidState(s')
    requires evalUserspaceExecution(s, s')
    requires var pt := ExtractAbsPageTable(s);
        pt.Just? && var pages := WritablePagesInTable(fromJust(pt));
        BitwiseMaskHigh(m, 12) !in pages
    requires m in s.m.addresses
    ensures (reveal_ValidMemState();
        s'.m.addresses[m] == s.m.addresses[m])
{
    reveal_ValidMemState();
    reveal_ValidRegState();
    var pt := ExtractAbsPageTable(s);
    assert pt.Just?;
    var pages := WritablePagesInTable(fromJust(pt));
    assert s'.m.addresses[m] == havocPages(pages, s.m.addresses, s'.m.addresses)[m];
    assert havocPages(pages, s.m.addresses, s'.m.addresses)[m] == s.m.addresses[m];
}

lemma onlyDataPagesAreWritable(p:PageNr,a:addr,d:PageDb,s:state, s':state,
    l1:PageNr)
    requires PhysBase() == KOM_DIRECTMAP_VBASE()
    requires ValidState(s) && ValidState(s') && evalUserspaceExecution(s,s')
    requires validPageDb(d) && d[p].PageDbEntryTyped? && !d[p].entry.DataPage?
    requires SaneMem(s.m) && pageDbCorresponds(s.m, d);
    requires WordAligned(a)
    requires addrInPage(a, p)
    requires s.conf.ttbr0.ptbase == page_paddr(l1);
    requires nonStoppedL1(d, l1);
    ensures var pt := ExtractAbsPageTable(s);
        pt.Just? && var pages := WritablePagesInTable(fromJust(pt));
        BitwiseMaskHigh(a, 12) !in pages
{
    reveal_validPageDb();

    var pt := ExtractAbsPageTable(s);
    assert pt.Just?;
    var pages := WritablePagesInTable(fromJust(pt));
    var vbase := s.conf.ttbr0.ptbase + PhysBase();
    var pagebase := BitwiseMaskHigh(a, 12);

    assert ExtractAbsL1PTable(s.m, vbase) == fromJust(pt);

    assert fromJust(pt) == mkAbsPTable(d, l1) by 
    {
        lemma_ptablesmatch(s.m, d, l1);    
    }
    assert WritablePagesInTable(fromJust(pt)) ==
        WritablePagesInTable(mkAbsPTable(d, l1));
    
    forall( a':addr, p':PageNr | 
        var pagebase' := BitwiseMaskHigh(a', 12);
        pagebase' in WritablePagesInTable(fromJust(pt)) &&
        addrInPage(a',p') )
        ensures d[p'].PageDbEntryTyped? && d[p'].entry.DataPage?
    {
        var pagebase' := BitwiseMaskHigh(a', 12);
        assert addrInPage(a', p') <==> addrInPage(pagebase', p') by {
            lemma_bitMaskAddrInPage(a', pagebase', p');
        }
        lemma_writablePagesAreDataPages(p', pagebase', d, l1);
    }
}

lemma lemma_writablePagesAreDataPages(p:PageNr,a:addr,d:PageDb,l1p:PageNr)
    requires PhysBase() == KOM_DIRECTMAP_VBASE()   
    requires validPageDb(d)     
    requires nonStoppedL1(d, l1p) 
    requires PageAligned(a) && address_is_secure(a) 
    requires a in WritablePagesInTable(mkAbsPTable(d, l1p)) 
    requires addrInPage(a, p)
    ensures  d[p].PageDbEntryTyped? && d[p].entry.DataPage?
{
    reveal_validPageDb();
    reveal_pageDbEntryCorresponds();
    reveal_pageContentsCorresponds();
    lemma_WritablePages(d, l1p, a);
}

lemma userspaceExecutionPreservesPageDb(d:PageDb,s:state,s':state, l1:PageNr)
    requires SaneMem(s.m) && SaneMem(s'.m) && validPageDb(d)
        && ValidState(s) && ValidState(s')
    requires evalUserspaceExecution(s,s')
    requires pageDbCorresponds(s.m,  d)
    requires s.conf.ttbr0.ptbase == page_paddr(l1);
    requires nonStoppedL1(d, l1);
    ensures  pageDbCorresponds(s'.m, d)
{
    reveal_PageDb();
    reveal_ValidMemState();
    reveal_pageDbEntryCorresponds();
    reveal_pageContentsCorresponds();


    forall ( p | validPageNr(p) )
        ensures pageDbEntryCorresponds(d[p], extractPageDbEntry(s'.m,p));
    {
        assert extractPageDbEntry(s.m, p) == extractPageDbEntry(s'.m, p);
        PageDbCorrespondsImpliesEntryCorresponds(s.m, d, p);
        assert pageDbEntryCorresponds(d[p], extractPageDbEntry(s.m, p));
        
    }

    var pt := ExtractAbsPageTable(s);
    assert pt.Just?;

    forall ( p | validPageNr(p) && d[p].PageDbEntryTyped? && 
        !d[p].entry.DataPage? )
        ensures pageContentsCorresponds(p, d[p], extractPage(s'.m, p));
    {
        forall ( a:addr | page_monvaddr(p) <= a < page_monvaddr(p) + PAGESIZE() )
            ensures s'.m.addresses[a] == s.m.addresses[a]
            {
               var pt := ExtractAbsPageTable(s);
               assert pt.Just?;
               var pages := WritablePagesInTable(fromJust(pt));

               onlyDataPagesAreWritable(p, a, d, s, s', l1);
               assert BitwiseMaskHigh(a, 12) !in pages;
               nonWritablePagesAreSafeFromHavoc(a, s, s'); 

               assert s'.m.addresses[a] == s.m.addresses[a];

            }
        assert extractPage(s.m, p) == extractPage(s'.m, p);
        assert pageContentsCorresponds(p, d[p], extractPage(s.m, p));
    }
}

lemma exceptionTakenPreservesPageDb(d:PageDb,s:state,ex:exception,s':state)
    requires SaneMem(s.m) && SaneMem(s'.m) && validPageDb(d)
        && ValidState(s) && ValidState(s')
    requires evalExceptionTaken(s, ex, s')
    requires pageDbCorresponds(s.m, d)
    ensures  pageDbCorresponds(s'.m, d)
{
    reveal_PageDb();
    reveal_ValidMemState();
    reveal_pageDbEntryCorresponds();
    reveal_pageContentsCorresponds();
}

// This is actually not true

/*
lemma appInvariantPreservesPageDb(d:PageDb,s:state,s':state)
    requires SaneMem(s.m) && SaneMem(s'.m) && validPageDb(d)
        && ValidState(s) && ValidState(s')
    requires ApplicationUsermodeContinuationInvariant(s, s')
    requires pageDbCorresponds(s.m , d)
    requires AUCIdef();
    ensures  pageDbCorresponds(s'.m, d)
{
    reveal_PageDb();
    reveal_ValidMemState();
    reveal_pageDbEntryCorresponds();
    reveal_pageContentsCorresponds();
    // TODO FIXME after defining
}
*/


// This is actually not true!
/*
lemma evalMOVSPCLRUCPreservesPageDb(d:PageDb, d':PageDb, s:state, r:state, l1:PageNr)
    requires ValidState(s) && ValidState(r)
    requires SaneMem(s.m) && SaneMem(r.m) && validPageDb(d)
    requires evalMOVSPCLRUC(s, r) && pageDbCorresponds(s.m, d)
    requires s.conf.ttbr0.ptbase == page_paddr(l1);
    requires nonStoppedL1(d, l1);
    requires AUCIdef()
{
    reveal_PageDb();
    reveal_ValidMemState();
    reveal_pageDbEntryCorresponds();
    reveal_pageContentsCorresponds();

    forall ( ex, s2, s3, s4 | ValidState(s2) && ValidState(s3) && ValidState(s4)
        && evalEnterUserspace(s, s2)
        && evalUserspaceExecution(s2, s3)
        && evalExceptionTaken(s3, ex, s4)
        && ApplicationUsermodeContinuationInvariant(s4, r)
        && r.ok )
        ensures  pageDbCorresponds(r.m, d)
    {
        enterUserspacePreservesPageDb(d, s,  s2);
        userspaceExecutionPreservesPageDb(d, s2, s3, l1); 
        exceptionTakenPreservesPageDb(d, s3, ex, s4);
        appInvariantPreservesPageDb(d, s4, r);
    }
}
*/

