include "sec_prop.s.dfy"
include "../pagedb.s.dfy"
include "../entry.s.dfy"
include "sec_prop_util.i.dfy"
include "conf_ni_entry.i.dfy"

//-----------------------------------------------------------------------------
// Proof that enclave contents are NI with the OS 
//-----------------------------------------------------------------------------

// Note: we are assuming the CPSR is trashed just after the smc call, which is 
// true of our implementation
predicate same_cpsr(s1:state, s2:state)
    requires ValidState(s1) && ValidState(s2)
{
    reveal ValidSRegState();
    s1.sregs[cpsr] == s2.sregs[cpsr]
}

lemma lemma_conf_ni(s1: state, d1: PageDb, s1': state, d1': PageDb,
                    s2: state, d2: PageDb, s2': state, d2': PageDb,
                    atkr: PageNr)
    requires ni_reqs(s1, d1, s1', d1', s2, d2, s2', d2', atkr)
    requires smchandler(s1, d1, s1', d1')
    requires smchandler(s2, d2, s2', d2')
    requires conf_loweq(s1, d1, s2, d2, atkr)
    requires same_cpsr(s1, s2)
    requires s1.conf.nondet == s2.conf.nondet
    ensures !(var callno := s1.regs[R0]; var asp := s1.regs[R1];
        callno == KOM_SMC_STOP && asp == atkr) ==>
        conf_loweq(s1', d1', s2', d2', atkr)
{
    reveal ValidRegState();
    var callno, arg1, arg2, arg3, arg4
        := s1.regs[R0], s1.regs[R1], s1.regs[R2], s1.regs[R3], s1.regs[R4];
    var e1', e2' := s1'.regs[R0], s2'.regs[R0];
    var val1, val2 := s1'.regs[R1], s2'.regs[R1];

    var entry := callno == KOM_SMC_ENTER || callno == KOM_SMC_RESUME;

    lemma_smchandlerInvariant_regs_ni(s1, s1', s2, s2', entry);

    if(callno == KOM_SMC_QUERY || callno == KOM_SMC_GETPHYSPAGES){
        // assert s1'.m == s1.m;
        // assert s2'.m == s2.m;
    }
    else if(callno == KOM_SMC_INIT_ADDRSPACE){
        lemma_initAddrspace_loweq_pdb(d1, d1', e1', d2, d2', e2', arg1, arg2, atkr);
        lemma_integrate_reg_equiv(s1', s2');
    }
    else if(callno == KOM_SMC_INIT_DISPATCHER){
        lemma_initDispatcher_loweq_pdb(d1, d1', e1', d2, d2', e2', arg1, arg2, 
            arg3, atkr);
        lemma_integrate_reg_equiv(s1', s2');
    }
    else if(callno == KOM_SMC_INIT_L2PTABLE){
        lemma_initL2PTable_loweq_pdb(d1, d1', e1', d2, d2', e2', arg1, arg2, 
            arg3, atkr);
        lemma_integrate_reg_equiv(s1', s2');
    }
    else if(callno == KOM_SMC_MAP_SECURE){
        var c1 := maybeContentsOfPhysPage(s1, arg4);
        var c2 := maybeContentsOfPhysPage(s2, arg4);
        assert contentsOk(arg4, c1) && contentsOk(arg4, c2) by
            { reveal loweq_pdb(); }
        lemma_maybeContents_insec_ni(s1, s2, c1, c2, arg4);
        assert c1 == c2;
        lemma_mapSecure_loweq_pdb(d1, d1', e1', c1, d2, d2', e2', c2,
            arg1, arg2, arg3, arg4, atkr);
        lemma_integrate_reg_equiv(s1', s2');
    }
    else if(callno == KOM_SMC_ALLOC_SPARE) {
        lemma_allocSpare_loweq_pdb(d1, d1', e1', d2, d2', e2', arg1, arg2, atkr);
    }
    else if(callno == KOM_SMC_MAP_INSECURE){
        lemma_mapInsecure_loweq_pdb(d1, d1', e1', d2, d2', e2', arg1, arg2, arg3, atkr);
        lemma_integrate_reg_equiv(s1', s2');
    }
    else if(callno == KOM_SMC_REMOVE){
        lemma_remove_loweq_pdb(d1, d1', e1', d2, d2', e2', arg1, atkr);
        lemma_integrate_reg_equiv(s1', s2');
    }
    else if(callno == KOM_SMC_FINALISE){
        lemma_finalise_loweq_pdb(d1, d1', e1', d2, d2', e2', arg1, atkr);
        lemma_integrate_reg_equiv(s1', s2');
    }
    else if(callno == KOM_SMC_ENTER){
        lemma_enter_conf_ni(
            s1, d1, s1', d1',
            s2, d2, s2', d2',
            arg1, arg2, arg3, arg4, atkr);
        assert os_regs_equiv(s1', s2') by {
            lemma_integrate_reg_equiv(s1', s2');
        }
        assert os_ctrl_eq(s1', s2') by {
            assert most_modes_ctrl_eq(s1', s2');
        }
    }
    else if(callno == KOM_SMC_RESUME){
        lemma_resume_conf_ni(
            s1, d1, s1', d1',
            s2, d2, s2', d2',
            arg1, atkr);
        assert os_regs_equiv(s1', s2') by {
            lemma_integrate_reg_equiv(s1', s2');
        }
        assert os_ctrl_eq(s1', s2') by {
            assert most_modes_ctrl_eq(s1', s2');
        }
    }
    else if(callno == KOM_SMC_STOP){
        lemma_stop_loweq_pdb(d1, d1', e1', d2, d2', e2', arg1, atkr);
        lemma_integrate_reg_equiv(s1', s2');
    }
    else {
        assert e1' == KOM_ERR_INVALID;
        assert e2' == KOM_ERR_INVALID;
        lemma_integrate_reg_equiv(s1', s2');
    }
}

predicate non_ret_os_regs_equiv(s1: state, s2: state)
    requires ValidState(s1) && ValidState(s2)
{
   reveal ValidRegState();
   reveal ValidSRegState();
   s1.regs[R2]  == s2.regs[R2] &&
   s1.regs[R3]  == s2.regs[R3] &&
   s1.regs[R4]  == s2.regs[R4] &&
   s1.regs[R5]  == s2.regs[R5] &&
   s1.regs[R6]  == s2.regs[R6] &&
   s1.regs[R7]  == s2.regs[R7] &&
   s1.regs[R8]  == s2.regs[R8] &&
   s1.regs[R9]  == s2.regs[R9] &&
   s1.regs[R10] == s2.regs[R10] &&
   s1.regs[R11] == s2.regs[R11] &&
   s1.regs[R12] == s2.regs[R12] &&
   s1.regs[LR(User)]       == s2.regs[LR(User)] &&
   // s1.regs[LR(FIQ)]        == s2.regs[LR(FIQ)] &&
   // s1.regs[LR(IRQ)]        == s2.regs[LR(IRQ)] &&
   s1.regs[LR(Supervisor)] == s2.regs[LR(Supervisor)] &&
   s1.regs[LR(Abort)]      == s2.regs[LR(Abort)] &&
   s1.regs[LR(Undefined)]  == s2.regs[LR(Undefined)] &&
   s1.regs[SP(User)]       == s2.regs[SP(User)] &&
   s1.regs[SP(FIQ)]        == s2.regs[SP(FIQ)] &&
   s1.regs[SP(IRQ)]        == s2.regs[SP(IRQ)] &&
   s1.regs[SP(Supervisor)] == s2.regs[SP(Supervisor)] &&
   s1.regs[SP(Abort)]      == s2.regs[SP(Abort)] &&
   s1.regs[SP(Undefined)]  == s2.regs[SP(Undefined)]
}

predicate most_modes_regs_equiv(s1: state, s2: state)
    requires ValidState(s1) && ValidState(s2)
{
   reveal ValidRegState();
   reveal ValidSRegState();
   s1.regs[R2]  == s2.regs[R2] &&
   s1.regs[R3]  == s2.regs[R3] &&
   s1.regs[R4]  == s2.regs[R4] &&
   s1.regs[R5]  == s2.regs[R5] &&
   s1.regs[R6]  == s2.regs[R6] &&
   s1.regs[R7]  == s2.regs[R7] &&
   s1.regs[R8]  == s2.regs[R8] &&
   s1.regs[R9]  == s2.regs[R9] &&
   s1.regs[R10] == s2.regs[R10] &&
   s1.regs[R11] == s2.regs[R11] &&
   s1.regs[R12] == s2.regs[R12] &&
   s1.regs[LR(User)]       == s2.regs[LR(User)] &&
   s1.regs[LR(Supervisor)] == s2.regs[LR(Supervisor)] &&
   s1.regs[LR(Abort)]      == s2.regs[LR(Abort)] &&
   s1.regs[LR(Undefined)]  == s2.regs[LR(Undefined)] &&
   s1.regs[SP(User)]       == s2.regs[SP(User)] &&
   s1.regs[SP(FIQ)]        == s2.regs[SP(FIQ)] &&
   s1.regs[SP(IRQ)]        == s2.regs[SP(IRQ)] &&
   s1.regs[SP(Supervisor)] == s2.regs[SP(Supervisor)] &&
   s1.regs[SP(Abort)]      == s2.regs[SP(Abort)] &&
   s1.regs[SP(Undefined)]  == s2.regs[SP(Undefined)]
}

predicate most_modes_ctrl_eq(s1: state, s2: state)
    requires ValidState(s1) && ValidState(s2)
{
    reveal ValidSRegState();
    var spsr_s  := spsr(Supervisor);
    var spsr_a  := spsr(Abort);
    var spsr_u  := spsr(Undefined);
    s1.sregs[spsr_s] == s2.sregs[spsr_s] &&
    s1.sregs[spsr_a] == s2.sregs[spsr_a] &&
    s1.sregs[spsr_u] == s2.sregs[spsr_u]
}

predicate ret_regs_equiv(s1:state, s2:state)
    requires ValidState(s1) && ValidState(s2)
{
    reveal ValidRegState();
    s1.regs[R0] == s2.regs[R0] &&
    s1.regs[R1] == s2.regs[R1]
}

lemma lemma_integrate_reg_equiv(s1: state, s2: state)
    requires ValidState(s1) && ValidState(s2)
    requires non_ret_os_regs_equiv(s1, s2)
    requires ret_regs_equiv(s1, s2)
    ensures  os_regs_equiv(s1, s2)
{
}

lemma lemma_smchandlerInvariant_regs_ni(
    s1: state, s1': state, s2: state, s2': state,
    entry: bool)
    requires ValidState(s1) && ValidState(s1')
    requires ValidState(s2) && ValidState(s2')
    requires smchandlerInvariant(s1, s1', entry)
    requires smchandlerInvariant(s2, s2', entry)
    requires os_regs_equiv(s1, s2)
    requires os_ctrl_eq(s1, s2)
    requires InsecureMemInvariant(s1, s2)
    ensures  os_ctrl_eq(s1', s2')
    ensures  non_ret_os_regs_equiv(s1', s2')
    ensures  !entry ==> InsecureMemInvariant(s1', s2')
{
}

lemma lemma_initAddrspace_loweq_pdb(
    d1: PageDb, d1': PageDb, e1': word,
    d2: PageDb, d2': PageDb, e2': word,
    addrspacePage: word, l1PTPage: word, atkr: PageNr)
    requires ni_reqs_(d1, d1', d2, d2', atkr)
    requires smc_initAddrspace(d1, addrspacePage, l1PTPage) == (d1', e1')
    requires smc_initAddrspace(d2, addrspacePage, l1PTPage) == (d2', e2')
    requires loweq_pdb(d1, d2, atkr)
    ensures  loweq_pdb(d1', d2', atkr)
    ensures  e1' == e2'
{
    reveal loweq_pdb();
}

lemma lemma_initDispatcher_loweq_pdb(
    d1: PageDb, d1': PageDb, e1': word,
    d2: PageDb, d2': PageDb, e2': word,
    page:word, addrspacePage:word, entrypoint:word,
    atkr: PageNr)
    requires ni_reqs_(d1, d1', d2, d2', atkr)
    requires smc_initDispatcher(d1, page, addrspacePage, entrypoint) == (d1', e1')
    requires smc_initDispatcher(d2, page, addrspacePage, entrypoint) == (d2', e2')
    requires loweq_pdb(d1, d2, atkr)
    ensures  loweq_pdb(d1', d2', atkr)
    ensures  e1' == e2'
{
    reveal loweq_pdb();
}

lemma lemma_initL2PTable_loweq_pdb(
    d1: PageDb, d1': PageDb, e1': word,
    d2: PageDb, d2': PageDb, e2': word,
    page: word, addrspacePage: word, l1index:word, atkr: PageNr)
    requires ni_reqs_(d1, d1', d2, d2', atkr)
    requires smc_initL2PTable(d1, page, addrspacePage, l1index) == (d1', e1')
    requires smc_initL2PTable(d2, page, addrspacePage, l1index) == (d2', e2')
    requires loweq_pdb(d1, d2, atkr)
    ensures  loweq_pdb(d1', d2', atkr)
    ensures  e1' == e2'
{
    reveal loweq_pdb();
}

lemma lemma_mapSecure_loweq_pdb(
    d1: PageDb, d1': PageDb, e1': word, c1: Maybe<seq<word>>,
    d2: PageDb, d2': PageDb, e2': word, c2: Maybe<seq<word>>,
    page: word, addrspacePage: word,
    mapping: word, physPage: word,
    atkr: PageNr)
    requires ni_reqs_(d1, d1', d2, d2', atkr)
    requires contentsOk(physPage, c1) && contentsOk(physPage, c2)
    requires c1 == c2;
    requires smc_mapSecure(d1, page, addrspacePage, mapping, physPage, c1) == (d1', e1')
    requires smc_mapSecure(d2, page, addrspacePage, mapping, physPage, c2) == (d2', e2')
    requires loweq_pdb(d1, d2, atkr)
    ensures  loweq_pdb(d1', d2', atkr)
    ensures  e1' == e2'
{
    reveal loweq_pdb();
    assert e1' == e2';
    if(e1' == KOM_ERR_SUCCESS) {
      lemma_mapSecure_loweq_pdb_success(d1, c1, d1', e1', d2, c2, d2', e2',
                            page, addrspacePage, mapping, 
                            physPage, atkr);
    }
}

lemma lemma_mapSecure_loweq_pdb_success(
        d1: PageDb, c1: Maybe<seq<word>>, d1': PageDb, e1':word,
        d2: PageDb, c2: Maybe<seq<word>>, d2': PageDb, e2':word,
        page:word, addrspacePage:word, mapping:word, 
        physPage: word, atkr: PageNr)
    requires ni_reqs_(d1, d1', d2, d2', atkr)
    requires contentsOk(physPage, c1) && contentsOk(physPage, c2)
    requires c1 == c2;
    requires e1' == KOM_ERR_SUCCESS && e2' == KOM_ERR_SUCCESS
    requires smc_mapSecure(d1, page, addrspacePage, mapping, physPage, c1) == (d1', e1')
    requires smc_mapSecure(d2, page, addrspacePage, mapping, physPage, c2) == (d2', e2')
    requires loweq_pdb(d1, d2, atkr)
    ensures  loweq_pdb(d1', d2', atkr) 
{
    assert d1'[atkr].PageDbEntryTyped? <==> d1[atkr].PageDbEntryTyped? by
        { reveal loweq_pdb(); }
    assert d2'[atkr].PageDbEntryTyped? <==> d2[atkr].PageDbEntryTyped? by
        { reveal loweq_pdb(); }
    assert d2'[atkr].PageDbEntryTyped? <==> d1'[atkr].PageDbEntryTyped? by
        { reveal loweq_pdb(); }
    if( d1'[atkr].PageDbEntryTyped? ){
        assert c1 == c2;
        var data := DataPage(fromJust(c1)); 
        var ap1 := allocatePage(d1, page, addrspacePage, data);
        var ap2 := allocatePage(d2, page, addrspacePage, data);
        allocatePagePreservesPageDBValidity(d1, page, addrspacePage, data);
        allocatePagePreservesPageDBValidity(d2, page, addrspacePage, data);
        lemma_allocatePage_loweq_pdb(d1, ap1.0, ap1.1, d2, ap2.0, ap2.1,
            page, addrspacePage, data, atkr);
        assert ap1.1 == e1';
        assert ap2.1 == e2';
        var abs_mapping := wordToMapping(mapping);
        var l2pte := SecureMapping(page, abs_mapping.perm.w, abs_mapping.perm.x);
        assert validL2PTE(ap1.0, addrspacePage, l2pte);
        assert validL2PTE(ap2.0, addrspacePage, l2pte);
        assert validAndEmptyMapping(abs_mapping, ap1.0, addrspacePage) by
            {reveal wordToMapping(); }
        assert validAndEmptyMapping(abs_mapping, ap2.0, addrspacePage) by
            {reveal wordToMapping(); }
        var db1 := updateL2Pte(ap1.0, addrspacePage, abs_mapping, l2pte); 
        var db2 := updateL2Pte(ap2.0, addrspacePage, abs_mapping, l2pte); 
        assert e1' == KOM_ERR_SUCCESS <==> e2' == KOM_ERR_SUCCESS;
        assert !pageIsFree(d1, page) ==> e1' != KOM_ERR_SUCCESS;
        assert !pageIsFree(d2, page) ==> e1' != KOM_ERR_SUCCESS;
        if(e1' == KOM_ERR_SUCCESS) {
            lemma_allocatePageRefs(d1, addrspacePage, page, data, ap1.0, e1');
            lemma_allocatePageRefs(d2, addrspacePage, page, data, ap2.0, e1');
            lemma_updateL2PtePreservesPageDb(ap1.0,addrspacePage,abs_mapping,l2pte);
            lemma_updateL2PtePreservesPageDb(ap2.0,addrspacePage,abs_mapping,l2pte);
            lemma_updateL2Pte_loweq_pdb(ap1.0, db1, ap2.0, db2, 
                addrspacePage, abs_mapping, l2pte, atkr);
            contentsDivBlock(physPage, c1);
            contentsDivBlock(physPage, c2);
            lemma_updateMeasurement_ni(db1, db2, d1', d2', addrspacePage,
                [KOM_SMC_MAP_SECURE, mapping], fromJust(c1), atkr);
            reveal loweq_pdb();
            assert loweq_pdb(d1', d2', atkr);
        } else {
            reveal loweq_pdb();
        }
    } else {
        reveal loweq_pdb();
        assert loweq_pdb(d1', d2', atkr);
    }
}

lemma lemma_mapInsecure_loweq_pdb(
    d1: PageDb, d1': PageDb, e1': word,
    d2: PageDb, d2': PageDb, e2': word,
    addrspacePage: word, mapping: word, physPage: word, atkr:PageNr)
    requires validPageDb(d1) && validPageDb(d2)
    requires validPageDb(d1') && validPageDb(d2')
    requires ni_reqs_(d1, d1', d2, d2', atkr)
    requires smc_mapInsecure(d1, addrspacePage, mapping, physPage) == (d1', e1')
    requires smc_mapInsecure(d2, addrspacePage, mapping, physPage) == (d2', e2')
    requires loweq_pdb(d1, d2, atkr)
    ensures  loweq_pdb(d1', d2', atkr)
    ensures  e1' == e2'
{
    reveal loweq_pdb();
}

lemma lemma_allocSpare_loweq_pdb(
    d1: PageDb, d1': PageDb, e1': word,
    d2: PageDb, d2': PageDb, e2': word,
    page: word, addrspacePage: word,
    atkr: PageNr)
    requires ni_reqs_(d1, d1', d2, d2', atkr)
    requires smc_allocSpare(d1, page, addrspacePage) == (d1', e1')
    requires smc_allocSpare(d2, page, addrspacePage) == (d2', e2')
    requires loweq_pdb(d1, d2, atkr)
    ensures  loweq_pdb(d1', d2', atkr)
    ensures  e1' == e2'
{
    reveal loweq_pdb();
}


lemma lemma_remove_loweq_pdb(
    d1: PageDb, d1': PageDb, e1': word,
    d2: PageDb, d2': PageDb, e2': word,
    page: word, atkr: PageNr)
    requires ni_reqs_(d1, d1', d2, d2', atkr)
    requires smc_remove(d1, page) == (d1', e1')
    requires smc_remove(d2, page) == (d2', e2')
    requires loweq_pdb(d1, d2, atkr)
    ensures  page != atkr ==>loweq_pdb(d1', d2', atkr) 
    ensures  e1' == e2'
{
    reveal loweq_pdb();
    reveal validPageDb();
}

lemma lemma_finalise_loweq_pdb(
    d1: PageDb, d1': PageDb, e1': word,
    d2: PageDb, d2': PageDb, e2': word,
    addrspacePage: word, atkr: PageNr)
    requires ni_reqs_(d1, d1', d2, d2', atkr)
    requires smc_finalise(d1, addrspacePage) == (d1', e1')
    requires smc_finalise(d2, addrspacePage) == (d2', e2')
    requires loweq_pdb(d1, d2, atkr)
    ensures  loweq_pdb(d1', d2', atkr)
    ensures  e1' == e2'
{
    reveal loweq_pdb();
}

lemma lemma_stop_loweq_pdb(
    d1: PageDb, d1': PageDb, e1': word,
    d2: PageDb, d2': PageDb, e2': word,
    addrspacePage: word, atkr: PageNr)
    requires ni_reqs_(d1, d1', d2, d2', atkr)
    requires smc_stop(d1, addrspacePage) == (d1', e1')
    requires smc_stop(d2, addrspacePage) == (d2', e2')
    requires loweq_pdb(d1, d2, atkr)
    ensures  addrspacePage != atkr ==> loweq_pdb(d1', d2', atkr)
    ensures  e1' == e2'
{
    reveal loweq_pdb();
    if(addrspacePage == atkr) {
    } else {
    }
}

lemma lemma_allocatePage_loweq_pdb(d1: PageDb, d1': PageDb, e1':word,
                                d2: PageDb, d2': PageDb, e2':word,
                                page: word, addrspacePage: PageNr,
                                entry: PageDbEntryTyped, atkr: PageNr)
    requires validPageDb(d1) && wellFormedPageDb(d1')
    requires validPageDb(d2) && wellFormedPageDb(d2')
    requires valAddrPage(d1, atkr) && valAddrPage(d2, atkr)
    requires isAddrspace(d1, addrspacePage) && 
        isAddrspace(d2, addrspacePage);
    requires allocatePageEntryValid(entry);
    requires allocatePage(d1, page, addrspacePage, entry) == (d1', e1')
    requires allocatePage(d2, page, addrspacePage, entry) == (d2', e2')
    requires loweq_pdb(d1, d2, atkr)
    ensures  loweq_pdb(d1', d2', atkr) 
    ensures  addrspacePage == atkr ==> e1' == e2'
{
    reveal loweq_pdb();
    assert allocatePage(d1, page, addrspacePage, entry) == (d1', e1');
    assert allocatePage(d2, page, addrspacePage, entry) == (d2', e2');
    if( atkr == addrspacePage ) {
        assert valAddrPage(d1', atkr);
        assert valAddrPage(d2', atkr);
        assert valAddrPage(d1', atkr) <==> valAddrPage(d2', atkr);
        assert (e1' == KOM_ERR_PAGEINUSE) <==> (e2' == KOM_ERR_PAGEINUSE);
       
        forall(n : PageNr)
            ensures pgInAddrSpc(d1', n, atkr) <==> pgInAddrSpc(d2', n, atkr)
         {
            if(n == atkr) {
                assert pgInAddrSpc(d1, n, atkr) <==> pgInAddrSpc(d1', n, atkr);
                assert pgInAddrSpc(d2, n, atkr) <==> pgInAddrSpc(d2', n, atkr);
            }
            if(n == page) {
                var as1 := d1[atkr].entry.state;
                assert (pageIsFree(d1, n) && as1 == InitState) ==>
                   pgInAddrSpc(d1', n, atkr);
            }
            if(n != page && n != atkr){
                assert pgInAddrSpc(d1, n, atkr) <==> pgInAddrSpc(d1', n, atkr);
                assert pgInAddrSpc(d2, n, atkr) <==> pgInAddrSpc(d2', n, atkr);
            }
         }
         forall( n : PageNr | pgInAddrSpc(d1', n, atkr)) 
             ensures d1'[n].entry == d2'[n].entry { 
             if(e1' == KOM_ERR_SUCCESS){
                assert d1'[atkr].entry == d2'[atkr].entry;
                assert d1'[page].entry == d2'[page].entry;
                if(n != atkr && n != page) {
                    assert d1'[n].entry == d1[n].entry;
                }
             }
        }
    } else {
        assert valAddrPage(d1, atkr);
        assert valAddrPage(d2, atkr);
        assert valAddrPage(d1', atkr);
        assert valAddrPage(d2', atkr);

        forall(n: PageNr)
            ensures pgInAddrSpc(d1', n, atkr) <==>
                pgInAddrSpc(d2', n, atkr)
        {
            assert pgInAddrSpc(d1, n, atkr) <==> pgInAddrSpc(d1', n, atkr);
            assert pgInAddrSpc(d2, n, atkr) <==> pgInAddrSpc(d2', n, atkr);
            if(n == addrspacePage){
                assert valAddrPage(d1, n) ==> d1[n].addrspace == n;
                assert valAddrPage(d2, n) ==> d2[n].addrspace == n;
            }
            if(validPageNr(addrspacePage) && n == page){
                var a := addrspacePage; 
                if(valAddrPage(d1, a)){
                    var as1 := d1[a].entry.state;
                    assert (pageIsFree(d1, n) && as1 == InitState) ==>
                       !pgInAddrSpc(d1', n, atkr);
                }
            }
        }
    }
}

lemma lemma_updateL2Pte_loweq_pdb(d1: PageDb, d1': PageDb,
                               d2: PageDb, d2': PageDb,
                               a: PageNr, mapping: Mapping, l2e: L2PTE,
                               atkr: PageNr)
    requires ni_reqs_(d1, d1', d2, d2', atkr)
    requires isAddrspace(d1, a) && isAddrspace(d2, a)
    requires validMapping(mapping, d1, a) && validMapping(mapping, d2, a)
    requires d1[a].entry.state.InitState? && d2[a].entry.state.InitState?
    requires validL2PTE(d1, a, l2e) && validL2PTE(d2, a, l2e)
    requires validL1PTable(d1, a, d1[d1[a].entry.l1ptnr].entry.l1pt)
    requires validL1PTable(d2, a, d2[d2[a].entry.l1ptnr].entry.l1pt)
    requires d1' == updateL2Pte(d1, a, mapping, l2e) 
    requires d2' == updateL2Pte(d2, a, mapping, l2e) 
    requires loweq_pdb(d1, d2, atkr)
    ensures  loweq_pdb(d1', d2', atkr) 
{
    reveal loweq_pdb();
    reveal validPageDb();
    var l11 := d1[d1[a].entry.l1ptnr].entry;
    var l12 := d2[d2[a].entry.l1ptnr].entry;
    var l1pte1 := fromJust(l11.l1pt[mapping.l1index]);
    var l1pte2 := fromJust(l12.l1pt[mapping.l1index]);
    assert d1[l1pte1].addrspace == a;
    assert d2[l1pte2].addrspace == a;
    forall( n: PageNr | n != l1pte1)
        ensures d1'[n] == d1[n]; 
        ensures pgInAddrSpc(d1', n, atkr) <==>
            pgInAddrSpc(d1, n, atkr) { }
    forall( n: PageNr | n != l1pte2)
        ensures d2'[n] == d2[n]; 
        ensures pgInAddrSpc(d1', n, atkr) <==>
            pgInAddrSpc(d1, n, atkr) { }
    assert d1'[l1pte1].PageDbEntryTyped?;
    assert d2'[l1pte2].PageDbEntryTyped?;
    assert d1'[l1pte1].addrspace == a;
    assert d2'[l1pte2].addrspace == a;
}

lemma lemma_updateMeasurement_ni(d1: PageDb, d2: PageDb, d1': PageDb, d2': PageDb,
    addrsp: PageNr, metadata:seq<word>, contents:seq<word>, atkr: PageNr)
    requires validPageDb(d1)  && validPageDb(d2)
    requires validPageDb(d1') && validPageDb(d2')
    requires valAddrPage(d1, addrsp) && valAddrPage(d2, addrsp)
    requires |metadata| <= SHA_BLOCKSIZE
    requires |contents| % SHA_BLOCKSIZE == 0
    requires d1' == updateMeasurement(d1, addrsp, metadata, contents)
    requires d2' == updateMeasurement(d2, addrsp, metadata, contents)
    requires valAddrPage(d1, atkr) && valAddrPage(d2, atkr)
    requires loweq_pdb(d1, d2, atkr)
    ensures loweq_pdb(d1', d2', atkr)
{
    reveal loweq_pdb();
    if(atkr == addrsp) {
        reveal validPageDb();
        assert d1'[addrsp] == d2'[addrsp];
        forall(n: PageNr | n != addrsp)
            ensures d1[n] == d1'[n]
            ensures d2[n] == d2'[n] 
            ensures pgInAddrSpc(d1, n, atkr) ==>
                pgInAddrSpc(d1', n, atkr)
            ensures pgInAddrSpc(d2, n, atkr) ==>
                pgInAddrSpc(d2', n, atkr)
            {}
        assert loweq_pdb(d1', d2', atkr);
    } else {
        assert loweq_pdb(d1', d2', atkr);
    }
}
