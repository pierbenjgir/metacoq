From Coq Require Import Program ssreflect ssrbool List.
From MetaCoq.Template Require Import config utils Kernames MCRelations.


From MetaCoq.PCUIC Require Import PCUICAst PCUICAstUtils PCUICPrimitive
  PCUICReduction   
  PCUICReflect PCUICWeakeningEnvConv PCUICWeakeningEnvTyp PCUICCasesContexts
  PCUICWeakeningConv PCUICWeakeningTyp
  PCUICContextConversionTyp
  PCUICTyping PCUICGlobalEnv PCUICInversion PCUICGeneration
  PCUICConfluence PCUICConversion
  PCUICUnivSubstitutionTyp
  PCUICCumulativity PCUICSR PCUICSafeLemmata
  PCUICValidity PCUICPrincipality PCUICElimination 
  PCUICOnFreeVars PCUICWellScopedCumulativity PCUICSN PCUICCanonicity.

From MetaCoq Require Import PCUICArities PCUICSpine.
From MetaCoq.PCUIC Require PCUICWcbvEval.

Section firstorder.

  Context {Σ : global_env_ext}.
  Context {Σb : list (kername × bool)}.
  
  Fixpoint plookup_env {A} (Σ : list (kername × A)) (kn : kername) {struct Σ} : option A :=
  match Σ with
  | [] => None
  | d :: tl => if eq_kername kn d.1 then Some d.2 else plookup_env tl kn
  end. 
  (* 
  Definition zo_type (t : term) :=
    match (PCUICAstUtils.decompose_app t).1 with
    | tProd _ _ _ => false
    | tSort _ => false
    | tInd (mkInd nm i) _ => match (plookup_env Σb nm) with 
                             | Some l => nth i l false | None => false
                             end
    | _ => true
    end. *)
  
  Definition firstorder_type (n k : nat) (t : term) :=
    match (PCUICAstUtils.decompose_app t).1 with
    | tInd (mkInd nm i) u => match (plookup_env Σb nm) with 
                             | Some b => b | None => false
                             end
    | tRel i => (k <=? i) && (i <? n + k)
    | _ => false
    end.
  (* 
  Definition firstorder_type (t : term) :=
    match (PCUICAstUtils.decompose_app t).1 with
    | tInd (mkInd nm i) _ => match (plookup_env Σb nm) with 
                             | Some l => nth i l false | None => false
                             end
    | _ => false
    end. *)
  
  Definition firstorder_con mind (c : constructor_body) :=
    let inds := #|mind.(ind_bodies)| in
    alli (fun k '({| decl_body := b ; decl_type := t ; decl_name := n|}) => 
      firstorder_type inds k t) 0
      (List.rev (c.(cstr_args) ++ mind.(ind_params)))%list.
  
  Definition firstorder_oneind mind (ind : one_inductive_body) :=
    forallb (firstorder_con mind) ind.(ind_ctors) && negb (Universe.is_level (ind_sort ind)).
    
  Definition firstorder_mutind (mind : mutual_inductive_body) :=
    (* if forallb (fun decl => firstorder_type decl.(decl_type)) mind.(ind_params) then *)
    forallb (firstorder_oneind mind) mind.(ind_bodies)
    (* else repeat false (length mind.(ind_bodies)). *).
  
  Definition firstorder_ind (i : inductive) :=
    match lookup_env Σ.1 (inductive_mind i) with
    | Some (InductiveDecl mind) =>
        check_recursivity_kind (lookup_env Σ) (inductive_mind i) Finite &&
        firstorder_mutind mind
    | _ => false
    end.
  
End firstorder.
  
Fixpoint firstorder_env' (Σ : global_declarations) :=
  match Σ with
  | nil => []
  | (nm, ConstantDecl _) :: Σ' => 
    let Σb := firstorder_env' Σ' in 
    ((nm, false) :: Σb)
  | (nm, InductiveDecl mind) :: Σ' => 
    let Σb := firstorder_env' Σ' in 
    ((nm, @firstorder_mutind Σb mind) :: Σb)
  end.                       

Definition firstorder_env (Σ : global_env_ext) :=
  firstorder_env' Σ.1.(declarations).

Section cf.

Context {cf : config.checker_flags}.

Definition isPropositional Σ ind b := 
  match lookup_env Σ (inductive_mind ind) with
  | Some (InductiveDecl mdecl) =>
    match nth_error mdecl.(ind_bodies) (inductive_ind ind) with 
    | Some idecl =>
      match destArity [] idecl.(ind_type) with
      | Some (_, s) => is_propositional s = b
      | None => False
      end
    | None => False
    end
  | _ => False
  end.

Inductive firstorder_value Σ Γ : term -> Prop :=
| firstorder_value_C i n ui u args pandi : 
   Σ ;;; Γ |- mkApps (tConstruct i n ui) args : 
   mkApps (tInd i u) pandi ->
   Forall (firstorder_value Σ Γ) args ->
   isPropositional Σ i false ->
   firstorder_value Σ Γ (mkApps (tConstruct i n ui) args).

Lemma firstorder_value_inds :
 forall (Σ : global_env_ext) (Γ : context) (P : term -> Prop),
(forall (i : inductive) (n : nat) (ui u : Instance.t)
   (args pandi : list term),
 Σ;;; Γ |- mkApps (tConstruct i n ui) args : mkApps (tInd i u) pandi ->
 Forall (firstorder_value Σ Γ) args ->
 Forall P args ->
 isPropositional (PCUICEnvironment.fst_ctx Σ) i false ->
 P (mkApps (tConstruct i n ui) args)) ->
forall t : term, firstorder_value Σ Γ t -> P t.
Proof.
  intros ? ? ? ?. fix rec 2. intros t [ ]. eapply H; eauto.
  clear - H0 rec.
  induction H0; econstructor; eauto.
Qed.

Lemma firstorder_ind_propositional {Σ : global_env_ext} i mind oind :
  squash (wf_ext Σ) ->
  declared_inductive Σ i mind oind ->
  @firstorder_ind Σ (firstorder_env Σ) i ->
  isPropositional Σ i false.
Proof.
  intros Hwf d. pose proof d as [d1 d2]. intros H. red in d1. unfold firstorder_ind in H.
  red. sq.
  unfold PCUICEnvironment.fst_ctx in *. rewrite d1 in H |- *.
  solve_all.
  unfold firstorder_mutind in H0.
  rewrite d2. eapply forallb_nth_error in H0; tea.
  erewrite d2 in H0. cbn in H0.
  unfold firstorder_oneind in H0. solve_all.
  destruct (ind_sort oind) eqn:E2; inv H1.
  eapply PCUICInductives.declared_inductive_type in d.
  rewrite d. rewrite E2.
  now rewrite destArity_it_mkProd_or_LetIn.
Qed.

Inductive firstorder_spine Σ (Γ : context) : term -> list term -> term -> Type :=
| firstorder_spine_nil ty ty' :
    isType Σ Γ ty ->
    isType Σ Γ ty' ->
    Σ ;;; Γ ⊢ ty ≤ ty' ->
    firstorder_spine Σ Γ ty [] ty'

| firstorder_spine_cons ty hd tl na i u args B B' mind oind :
    isType Σ Γ ty ->
    isType Σ Γ (tProd na (mkApps (tInd i u) args) B) ->
    Σ ;;; Γ ⊢ ty ≤ tProd na (mkApps (tInd i u) args) B ->
    declared_inductive Σ i mind oind ->
    Σ ;;; Γ |- hd : (mkApps (tInd i u) args) ->
    @firstorder_ind Σ (@firstorder_env Σ) i ->
    firstorder_spine Σ Γ (subst10 hd B) tl B' ->
    firstorder_spine Σ Γ ty (hd :: tl) B'.

Inductive instantiated {Σ} (Γ : context) : term -> Type :=
| instantiated_mkApps i u args : instantiated Γ (mkApps (tInd i u) args)
| instantiated_LetIn na d b ty : 
  instantiated Γ (ty {0 := d}) ->
  instantiated Γ (tLetIn na d b ty)
| instantiated_tProd na B i u args : 
  @firstorder_ind Σ (@firstorder_env Σ) i ->
    (forall x,
       (* Σ ;;; Γ |- x : mkApps (tInd i u) args ->  *)
      instantiated Γ (subst10 x B)) ->
    instantiated Γ (tProd na (mkApps (tInd i u) args) B).

Import PCUICLiftSubst.
Lemma isType_context_conversion {Σ : global_env_ext} {wfΣ : wf Σ} {Γ Δ} {T} :
  isType Σ Γ T ->
  Σ ⊢ Γ = Δ ->
  wf_local Σ Δ ->
  isType Σ Δ T.
Proof.
  intros [s Hs]. exists s. eapply context_conversion; tea. now eapply ws_cumul_ctx_pb_forget.
Qed.

Lemma typing_spine_arity_spine {Σ : global_env_ext} {wfΣ : wf Σ} Γ Δ args T' i u pars :
  typing_spine Σ Γ (it_mkProd_or_LetIn Δ (mkApps (tInd i u) pars)) args T' ->
  arity_spine Σ Γ (it_mkProd_or_LetIn Δ (mkApps (tInd i u) pars)) args T'.
Proof.
  intros H. revert args pars T' H.
  induction Δ using PCUICInduction.ctx_length_rev_ind; intros args pars T' H.
  - cbn. depelim H.
    + econstructor; eauto.
    + eapply invert_cumul_ind_prod in w. eauto.
  - cbn. depelim H.
    + econstructor; eauto.
    + rewrite it_mkProd_or_LetIn_app in w, i0 |- *. cbn. destruct d as [name [body |] type]; cbn in *.
      -- constructor. rewrite /subst1 PCUICLiftSubst.subst_it_mkProd_or_LetIn subst_mkApps. eapply X. now len.
         econstructor; tea. eapply isType_tLetIn_red in i0.
         rewrite /subst1 PCUICLiftSubst.subst_it_mkProd_or_LetIn subst_mkApps Nat.add_0_r in i0. now rewrite Nat.add_0_r. pcuic.
         etransitivity; tea. eapply into_ws_cumul_pb. 2,4:fvs.
         econstructor 3. 2:{ econstructor. }
         rewrite /subst1 PCUICLiftSubst.subst_it_mkProd_or_LetIn subst_mkApps //. constructor 1. reflexivity.
         eapply isType_tLetIn_red in i0. 2:pcuic.
         rewrite /subst1 PCUICLiftSubst.subst_it_mkProd_or_LetIn subst_mkApps in i0.
         now eapply isType_open.
      -- eapply cumul_Prod_inv in w as []. econstructor.
         ++ eapply type_ws_cumul_pb. 3: eapply PCUICContextConversion.ws_cumul_pb_eq_le; symmetry. all:eauto.
            eapply isType_tProd in i0. eapply i0. 
         ++ rewrite /subst1 PCUICLiftSubst.subst_it_mkProd_or_LetIn. autorewrite with subst.
            cbn. eapply X. len. lia.
            eapply typing_spine_strengthen. eauto.
            2:{ replace (it_mkProd_or_LetIn (subst_context [hd] 0 Γ0)
            (mkApps (tInd i u) (map (subst [hd] (#|Γ0| + 0)) pars))) with ((PCUICAst.subst10 hd (it_mkProd_or_LetIn Γ0 (mkApps (tInd i u) pars)))).
            2:{ rewrite /subst1 PCUICLiftSubst.subst_it_mkProd_or_LetIn. now autorewrite with subst. }   
            eapply substitution0_ws_cumul_pb. eauto. eauto.
            }
            replace (it_mkProd_or_LetIn (subst_context [hd] 0 Γ0)
            (mkApps (tInd i u) (map (subst [hd] (#|Γ0| + 0)) pars))) with ((PCUICAst.subst10 hd (it_mkProd_or_LetIn Γ0 (mkApps (tInd i u) pars)))).
            2:{ rewrite /subst1 PCUICLiftSubst.subst_it_mkProd_or_LetIn. now autorewrite with subst. }   
            eapply isType_subst. eapply PCUICSubstitution.subslet_ass_tip. eauto.
            eapply isType_tProd in i0 as [_ tprod].
            eapply isType_context_conversion; tea. constructor. eapply ws_cumul_ctx_pb_refl. now eapply typing_wf_local, PCUICClosedTyp.wf_local_closed_context in t.
            constructor; tea. constructor. pcuic. eapply validity in t. now eauto.
Qed.
    
Lemma leb_spect : forall x y : nat, BoolSpecSet (x <= y) (y < x) (x <=? y).
Proof.
  intros x y. destruct (x <=? y) eqn:E;
  econstructor; destruct (Nat.leb_spec x y); lia.
Qed.

Lemma nth_error_inds {ind u mind n} : n < #|ind_bodies mind| ->
  nth_error (inds ind u mind.(ind_bodies)) n = Some (tInd (mkInd ind (#|mind.(ind_bodies)| - S n)) u).
Proof.
  unfold inds.
  induction #|ind_bodies mind| in n |- *.
  - intros hm. inv hm.
  - intros hn. destruct n => /=. lia_f_equal.
    eapply IHn0. lia.
Qed.

Lemma alli_subst_instance (Γ : context) u p : 
  (forall k t, p k t = p k t@[u]) ->
  forall n, 
    alli (fun (k : nat) '{| decl_type := t |} => p k t) n Γ = 
    alli (fun (k : nat) '{| decl_type := t |} => p k t) n Γ@[u].
Proof.
  intros hp.
  induction Γ; cbn => //.
  move=> n. destruct a; cbn. f_equal. apply hp. apply IHΓ.
Qed.

Lemma plookup_env_lookup_env Σ kn b : 
  plookup_env (firstorder_env Σ) kn = Some b ->
  ∑ decl, lookup_env Σ kn = Some decl ×
    match decl with 
    | ConstantDecl _ => b = false
    | InductiveDecl mind =>
      b = check_recursivity_kind (lookup_env Σ) kn Finite &&
          firstorder_mutind (Σb := firstorder_env Σ) mind
    end.
Proof using.
  destruct Σ as [[univs Σ] ext].
  induction Σ; cbn => //.
  destruct a as [kn' d] => //. cbn.
  case: eqb_specT.
  * intros ->. eexists; split => //.
    destruct d => //. cbn in H. rewrite eqb_refl in H. congruence. admit.
  (* intros neq h. specialize (IHΣ h) as [decl [Hdecl ?]].
      eexists; split => //. exact Hdecl.
      destruct decl => //. cbn.
      rewrite /lookup_env /=. rewrite y. f_equal.
      unfold check_recursivity_kind. case: eqb_spec => //.
      unfold firstorder_mutind. unfold firstorder_oneind.
      eapply forallb_ext. intros x. f_equal.
      eapply forallb_ext. intros cstr. unfold firstorder_con.
      eapply alli_ext => i' [] => /= _ _ ty.
      unfold firstorder_type.
      admit.
  - cbn.
*)
Admitted.

Lemma firstorder_spine_let {Σ : global_env_ext} {wfΣ : wf Σ} {Γ na a A B args T'} :
  firstorder_spine Σ Γ (B {0 := a}) args T' ->
  isType Σ Γ (tLetIn na a A B) ->
  firstorder_spine Σ Γ (tLetIn na a A B) args T'.
Proof.
  intros H; depind H.
  - constructor; auto.
    etransitivity; tea. eapply cumulSpec_cumulAlgo_curry; tea; fvs.
    eapply cumul_zeta.
  - intros. econstructor. tea.
    2:{ etransitivity; tea.
        eapply cumulSpec_cumulAlgo_curry; tea; fvs.
        eapply cumul_zeta. }
    all:tea.
Qed.

Lemma instantiated_typing_spine_firstorder_spine {Σ : global_env_ext} {wfΣ : wf Σ} Γ T args T' : 
  instantiated (Σ := Σ) Γ T ->
  arity_spine Σ Γ T args T' ->
  isType Σ Γ T ->
  firstorder_spine Σ Γ T args T'.
Proof.
  intros hi hsp.
  revert hi; induction hsp; intros hi isty.
  - constructor => //. now eapply isType_ws_cumul_pb_refl.
  - econstructor; eauto.
  - depelim hi. solve_discr. eapply firstorder_spine_let; eauto. eapply IHhsp => //.
    now eapply isType_tLetIn_red in isty; pcuic.
  - depelim hi. solve_discr.
    specialize (i1 hd). specialize (IHhsp i1).
    destruct (validity t) as [s Hs]. eapply inversion_mkApps in Hs as [? [hi _]].
    eapply inversion_Ind in hi as [mdecl [idecl [decli [? ?]]]].
    econstructor; tea. 2:{ eapply IHhsp. eapply isType_apply in isty; tea. }
    now eapply isType_ws_cumul_pb_refl. eauto.
Qed.

Lemma firstorder_args {Σ : global_env_ext} {wfΣ : wf Σ} { mind cbody i n ui args u pandi oind} :
  declared_constructor Σ (i, n) mind oind cbody ->
  PCUICArities.typing_spine Σ [] (type_of_constructor mind cbody (i, n) ui) args (mkApps (tInd i u) pandi) ->
  @firstorder_ind Σ (@firstorder_env Σ) i ->
  firstorder_spine Σ [] (type_of_constructor mind cbody (i, n) ui) args (mkApps (tInd i u) pandi).
Proof.
  intros Hdecl Hspine Hind. revert Hspine.
  unshelve edestruct @declared_constructor_inv with (Hdecl := Hdecl); eauto. eapply weaken_env_prop_typing.

  (* revert Hspine. *) unfold type_of_constructor.
  erewrite cstr_eq. 2: eapply p.
  rewrite <- it_mkProd_or_LetIn_app.
  rewrite PCUICUnivSubst.subst_instance_it_mkProd_or_LetIn. 
  rewrite PCUICSpine.subst0_it_mkProd_or_LetIn. intros Hspine.

  match goal with
   | [ |- firstorder_spine _ _ ?T _ _ ] =>
  assert (@instantiated Σ [] T) as Hi end.
  { clear Hspine. destruct Hdecl as [[d1 d3] d2]. pose proof d3 as Hdecl.
    unfold firstorder_ind in Hind. 
    rewrite d1 in Hind. solve_all. clear a.
    eapply forallb_nth_error in H0 as H'.
    erewrite d3 in H'.
    unfold firstorder_oneind in H'. cbn in H'.
    rtoProp.
    eapply nth_error_forallb in H1. 2: eauto.
    unfold firstorder_con in H1.
    revert H1. cbn.
    unfold cstr_concl. 
    rewrite PCUICUnivSubst.subst_instance_mkApps subst_mkApps.
    rewrite subst_instance_length app_length.
    unfold cstr_concl_head. rewrite PCUICInductives.subst_inds_concl_head. now eapply nth_error_Some_length in Hdecl.
    rewrite -app_length.
    generalize (cstr_args cbody ++ ind_params mind)%list. clear -d1 H H0 Hdecl.
    (* generalize conclusion to mkApps tInd args *)
    intros c. 
    change (list context_decl) with context in c.
    move: (map (subst (inds _ _ _) _) _).
    intros args.
    rewrite (alli_subst_instance _ ui (fun k t => firstorder_type #|ind_bodies mind| k t)).
    { intros k t.
      rewrite /firstorder_type. 
      rewrite -PCUICUnivSubstitutionConv.subst_instance_decompose_app /=.
      destruct (decompose_app) => //=. destruct t0 => //. }
    replace (List.rev c)@[ui] with (List.rev c@[ui]).
    2:{ rewrite /subst_instance /subst_instance_context /map_context map_rev //. }
    revert args.
    induction (c@[ui]) using PCUICInduction.ctx_length_rev_ind => args.
    - unfold cstr_concl, cstr_concl_head. cbn.
      autorewrite with substu subst.
      rewrite subst_context_nil. cbn -[subst0].
      econstructor.
    - rewrite rev_app_distr /=. destruct d as [na [b|] t]. 
      + move=> /andP[] fot foΓ.
        rewrite subst_context_app /=.
        rewrite it_mkProd_or_LetIn_app /= /mkProd_or_LetIn /=.
        constructor.
        rewrite /subst1 PCUICLiftSubst.subst_it_mkProd_or_LetIn subst_mkApps /=. len.
        rewrite -subst_app_context' // PCUICSigmaCalculus.subst_context_decompo.
        cbn. len. eapply X. now len.
        rewrite -subst_telescope_subst_context. clear -foΓ.
        revert foΓ. move: (lift0 #|ind_bodies mind| _).
        generalize 0.
        induction (List.rev Γ) => //.
        cbn -[subst_telescope]. intros n t. 
        destruct a; cbn -[subst_telescope].
        move/andP => [] fo fol.
        rewrite PCUICContextSubst.subst_telescope_cons /=.
        apply/andP; split; eauto.
        clear -fo.
        move: fo.
        unfold firstorder_type; cbn.
        destruct (decompose_app decl_type) eqn:da.
        rewrite (decompose_app_inv da) subst_mkApps /=.
        destruct t0 => //=.
        { move/andP => [/Nat.leb_le hn /Nat.ltb_lt hn'].
          destruct (Nat.leb_spec n n0).
          destruct (n0 - n) eqn:E. lia.
          cbn. rewrite nth_error_nil /=.
          rewrite decompose_app_mkApps //=.
          apply/andP. split. apply Nat.leb_le. lia. apply Nat.ltb_lt. lia.
          cbn.
          rewrite decompose_app_mkApps //=.
          apply/andP. split. apply Nat.leb_le. lia. apply Nat.ltb_lt. lia. }
        { destruct ind => //. rewrite decompose_app_mkApps //. }
      + move=> /andP[] fot foΓ.
        rewrite subst_context_app /=.
        rewrite it_mkProd_or_LetIn_app /= /mkProd_or_LetIn /=.
        unfold firstorder_type in fot.
        destruct ((PCUICAstUtils.decompose_app t)) eqn:E.
        cbn in fot. destruct t0; try solve [inv fot].
        * rewrite (decompose_app_inv E) /= subst_mkApps.
          rewrite Nat.add_0_r in fot. eapply Nat.ltb_lt in fot.
          cbn. rewrite nth_error_inds. lia. cbn.
          econstructor.
          { rewrite /firstorder_ind d1 H H0 //. }
          intros x.
          rewrite /subst1 PCUICLiftSubst.subst_it_mkProd_or_LetIn subst_mkApps /=. len.
          rewrite -subst_app_context' // PCUICSigmaCalculus.subst_context_decompo.
          cbn. len. eapply X. now len.
          rewrite -subst_telescope_subst_context. clear -foΓ.
          revert foΓ. generalize (lift0 #|ind_bodies mind| x).
          generalize 0.
          induction (List.rev Γ) => //.
          cbn -[subst_telescope]. intros n t. 
          destruct a; cbn -[subst_telescope].
          move/andP => [] fo fol.
          rewrite PCUICContextSubst.subst_telescope_cons /=.
          apply/andP; split; eauto.
          clear -fo.
          move: fo.
          unfold firstorder_type; cbn.
          destruct (decompose_app decl_type) eqn:da.
          rewrite (decompose_app_inv da) subst_mkApps /=.
          destruct t0 => //=.
          { move/andP => [/Nat.leb_le hn /Nat.ltb_lt hn'].
            destruct (Nat.leb_spec n n0).
            destruct (n0 - n) eqn:E. lia.
            cbn. rewrite nth_error_nil /=.
            rewrite decompose_app_mkApps //=.
            apply/andP. split. apply Nat.leb_le. lia. apply Nat.ltb_lt. lia.
            cbn.
            rewrite decompose_app_mkApps //=.
            apply/andP. split. apply Nat.leb_le. lia. apply Nat.ltb_lt. lia. }
          { destruct ind => //. rewrite decompose_app_mkApps //. }
        * rewrite (decompose_app_inv E) subst_mkApps //=.
          constructor. {
             unfold firstorder_ind. destruct ind. cbn in *.
             destruct plookup_env eqn:hp => //.
             eapply plookup_env_lookup_env in hp as [decl [eq ]].
             rewrite eq. destruct decl; subst b => //. }
          intros x. rewrite /subst1 PCUICLiftSubst.subst_it_mkProd_or_LetIn subst_mkApps /=; len.
          rewrite -subst_app_context' // PCUICSigmaCalculus.subst_context_decompo.
          eapply X. now len. len.
          rewrite -subst_telescope_subst_context. clear -foΓ.
          revert foΓ. generalize (lift0 #|ind_bodies mind| x).
          generalize 0.
          induction (List.rev Γ) => //.
          cbn -[subst_telescope]. intros n t. 
          destruct a; cbn -[subst_telescope].
          move/andP => [] fo fol.
          rewrite PCUICContextSubst.subst_telescope_cons /=.
          apply/andP; split; eauto.
          clear -fo.
          move: fo.
          unfold firstorder_type; cbn.
          destruct (decompose_app decl_type) eqn:da.
          rewrite (decompose_app_inv da) subst_mkApps /=.
          destruct t0 => //=.
          { move/andP => [/Nat.leb_le hn /Nat.ltb_lt hn'].
            destruct (Nat.leb_spec n n0).
            destruct (n0 - n) eqn:E. lia.
            cbn. rewrite nth_error_nil /=.
            rewrite decompose_app_mkApps //=.
            apply/andP. split. apply Nat.leb_le. lia. apply Nat.ltb_lt. lia.
            cbn.
            rewrite decompose_app_mkApps //=.
            apply/andP. split. apply Nat.leb_le. lia. apply Nat.ltb_lt. lia. }
          { destruct ind => //. rewrite decompose_app_mkApps //. }
  }
  cbn in Hi |- *.
  revert Hi Hspine. cbn.
  unfold cstr_concl, cstr_concl_head.
  autorewrite with substu subst.
  rewrite subst_instance_length app_length.
  rewrite PCUICInductives.subst_inds_concl_head. { cbn. destruct Hdecl as [[d1 d2] d3]. eapply nth_error_Some. rewrite d2. congruence. }
  match goal with [ |- context[mkApps _ ?args]] => generalize args end. 
  intros args' Hi Spine.
  eapply instantiated_typing_spine_firstorder_spine; tea.
  now eapply typing_spine_arity_spine in Spine.
  now eapply typing_spine_isType_dom in Spine.
Qed.

Lemma invert_cumul_it_mkProd_or_LetIn_Sort_Ind {Σ : global_env_ext} {wfΣ : wf Σ} {Γ Δ s i u args} :
  Σ ;;; Γ ⊢ it_mkProd_or_LetIn Δ (tSort s) ≤ mkApps (tInd i u) args -> False.
Proof.
  induction Δ using PCUICInduction.ctx_length_rev_ind; cbn.
  - eapply invert_cumul_sort_ind.
  - rewrite it_mkProd_or_LetIn_app; destruct d as [na [b|] ty]; cbn.
    * intros hl. 
      eapply ws_cumul_pb_LetIn_l_inv in hl.
      rewrite /subst1 PCUICLiftSubst.subst_it_mkProd_or_LetIn in hl.
      eapply H, hl. now len.
    * intros hl. now eapply invert_cumul_prod_ind in hl.
Qed.

Lemma firstorder_value_spec Σ t i u args mind :
  wf_ext Σ -> wf_local Σ [] ->
   Σ ;;; [] |- t : mkApps (tInd i u) args -> 
  PCUICWcbvEval.value Σ t -> 
  lookup_env Σ (i.(inductive_mind)) = Some (InductiveDecl mind) ->
  @firstorder_ind Σ (firstorder_env Σ) i ->
  firstorder_value Σ [] t.
Proof.
  intros Hwf Hwfl Hty Hvalue.
  revert mind i u args Hty. 
  
  induction Hvalue as [ t Hvalue | t args' Hhead Hargs IH ] using PCUICWcbvEval.value_values_ind; 
   intros mind i u args Hty Hlookup Hfo.
  - destruct t; inversion_clear Hvalue.
    + exfalso. eapply inversion_Sort in Hty as (? & ? & Hcumul); eauto.
      now eapply invert_cumul_sort_ind in Hcumul.
    + exfalso. eapply inversion_Prod in Hty as (? & ? & ? & ? & Hcumul); eauto.
      now eapply invert_cumul_sort_ind in Hcumul.
    + exfalso. eapply inversion_Lambda in Hty as (? & ? & ? & ? & Hcumul); eauto.
      now eapply invert_cumul_prod_ind in Hcumul.
    + exfalso. eapply inversion_Ind in Hty as (? & ? & ? & ? & ? & ?); eauto.
      eapply PCUICInductives.declared_inductive_type in d.
      rewrite d in w.
      destruct (ind_params x ,,, ind_indices x0) as [ | [? [] ?] ? _] using rev_ind.
      * cbn in w. now eapply invert_cumul_sort_ind in w.
      * rewrite it_mkProd_or_LetIn_app in w. cbn in w.
        eapply ws_cumul_pb_LetIn_l_inv in w.
        rewrite /subst1 PCUICUnivSubst.subst_instance_it_mkProd_or_LetIn PCUICLiftSubst.subst_it_mkProd_or_LetIn in w.
        now eapply invert_cumul_it_mkProd_or_LetIn_Sort_Ind in w.
      * rewrite it_mkProd_or_LetIn_app in w. cbn in w. 
        now eapply invert_cumul_prod_ind in w.
    + eapply inversion_Construct in Hty as Hty'; eauto.
      destruct Hty' as (? & ? & ? & ? & ? & ? & ?).
      assert (ind = i) as ->. {
         eapply PCUICInductiveInversion.Construct_Ind_ind_eq with (args0 := []); eauto.
      }
      eapply firstorder_value_C with (args := []); eauto.
      eapply firstorder_ind_propositional; eauto. sq. eauto.      
      now eapply (declared_constructor_inductive (ind := (i, _))).
    + exfalso. eapply invert_fix_ind with (args0 := []) in Hty as [].
      destruct unfold_fix as [ [] | ]; auto. eapply nth_error_nil.
    + exfalso. eapply (typing_cofix_coind (args := [])) in Hty. red in Hty.
      red in Hfo. unfold firstorder_ind in Hfo.
      rewrite Hlookup in Hfo.
      eapply andb_true_iff in Hfo as [Hfo _].
      eapply check_recursivity_kind_inj in Hty; eauto. congruence.
  - destruct t; inv Hhead.
    + exfalso. now eapply invert_ind_ind in Hty.
    + apply inversion_mkApps in Hty as Hcon; auto.
      destruct Hcon as (?&typ_ctor& spine).
      apply inversion_Construct in typ_ctor as (?&?&?&?&?&?&?); auto.
      pose proof d as [[d' _] _]. red in d'. cbn in *. unfold PCUICEnvironment.fst_ctx in *.
      eapply @PCUICInductiveInversion.Construct_Ind_ind_eq with (mdecl := x0) in Hty as Hty'; eauto.
      destruct Hty' as (([[[]]] & ?)  & ? & ? & ? & ? & _). subst.
      econstructor; eauto.
      2:{ eapply firstorder_ind_propositional; sq; eauto. eapply declared_constructor_inductive in d. eauto. }
      eapply PCUICSpine.typing_spine_strengthen in spine. 3: eauto. 
      2: eapply PCUICInductiveInversion.declared_constructor_valid_ty; eauto.

      eapply firstorder_args in spine; eauto.         
      clear c0 c1 e0 w Hty H0 Hargs.
      induction spine.
      * econstructor.
      * destruct d as [d1 d2]. inv IH.
        econstructor. inv X.
        eapply H0. tea. eapply d0. exact i3.
        inv X. eapply IHspine; eauto.
     + exfalso.
       destruct PCUICWcbvEval.cunfold_fix as [[] | ] eqn:E; inversion H.
       eapply invert_fix_ind in Hty. auto.
       unfold unfold_fix. unfold PCUICWcbvEval.cunfold_fix in E.
       destruct (nth_error mfix idx); auto.
       inversion E; subst; clear E.
       eapply nth_error_None. lia.
    + exfalso. eapply (typing_cofix_coind (args := args')) in Hty.
      red in Hfo. unfold firstorder_ind in Hfo.
      rewrite Hlookup in Hfo.
      eapply andb_true_iff in Hfo as [Hfo _].
      eapply check_recursivity_kind_inj in Hty; eauto. congruence.
Qed.

End cf.