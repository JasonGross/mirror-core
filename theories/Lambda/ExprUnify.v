Require Import Coq.Lists.List.
Require Import ExtLib.Core.RelDec.
Require Import ExtLib.Data.ListNth.
Require Import ExtLib.Data.HList.
Require Import ExtLib.Data.Fun.
Require Import ExtLib.Tactics.
Require Import MirrorCore.EnvI.
Require Import MirrorCore.ExprI.
Require Import MirrorCore.SymI.
Require Import MirrorCore.SubstI3.
Require Import MirrorCore.TypesI.
Require Import MirrorCore.Lambda.ExprCore.
Require Import MirrorCore.Lambda.ExprD.
Require Import MirrorCore.Lambda.ExprLift.

(** TODO **)
(* Require Import FunctionalExtensionality. *)

Set Implicit Arguments.
Set Strict Implicit.

Section typed.
  Variable subst : Type.
  Variable typ : Type.
  Variable func : Type.
  Variable RType_typ : RType typ.
  Variable Typ2_arr : Typ2 _ Fun.
  Variable RSym_func : RSym func.
  Variable RSymOk_func : RSymOk RSym_func.
  Variable Subst_subst : Subst subst (expr typ func).
  Variable SubstUpdate_subst : SubstUpdate subst (expr typ func).
  Variable SubstOk_subst : SubstOk (Expr_expr) Subst_subst.
  Variable SubstUpdateOk_subst
  : @SubstUpdateOk _ _ _ _ Expr_expr _ SubstUpdate_subst _.
  Local Instance Expr_expr : Expr _ (expr typ func) := Expr_expr.

  Local Instance RelDec_Rty ts : RelDec (Rty ts) :=
  { rel_dec := fun a b => match type_cast ts a b with
                            | Some _ => true
                            | None => false
                          end }.

  Section nested.
    Variable ts : list Type.

    (** n is the number of binders that we have gone under **)
    Variable exprUnify : forall (tus tvs : tenv typ) (under : nat) (s : subst)
                                (l r : expr typ func), typ -> option subst.

    Fixpoint exprUnify' (us vs : tenv typ) (n : nat) (s : subst)
             (e1 e2 : expr typ func) (t : typ) {struct e1}
    : option subst :=
      match e1 , e2 with
        | UVar u1 , UVar u2 =>
          if EqNat.beq_nat u1 u2 then Some s
          else
            match lookup u1 s , lookup u2 s with
              | None , None =>
                match set u1 (UVar u2) s with
                  | None =>
                    set u2 (UVar u1) s
                  | Some s => Some s
                end
              | Some e1' , None =>
                set u2 e1' s
              | None , Some e2' =>
                set u1 e2' s
              | Some e1' , Some e2' =>
                exprUnify us vs n s (lift 0 n e1') (lift 0 n e2') t
            end
        | UVar u1 , _ =>
          match lookup u1 s with
            | None =>
              match lower 0 n e2 with
                | None => None
                | Some e2 => set u1 e2 s
              end
            | Some e1' => exprUnify us vs n s (lift 0 n e1') e2 t
          end
        | _ , UVar u2 =>
          match lookup u2 s with
            | None =>
              match lower 0 n e1 with
                | None => None
                | Some e1 => set u2 e1 s
              end
            | Some e2' => exprUnify us vs n s e1 (lift 0 n e2') t
          end
        | Var v1 , Var v2 =>
          if EqNat.beq_nat v1 v2 then Some s else None
        | Inj f1 , Inj f2 =>
          match sym_eqb f1 f2 with
            | Some true => Some s
            | _ => None
          end
        | App e1 e1' , App e2 e2' =>
          match typeof_expr ts us vs e1 , typeof_expr ts us vs e2 with
            | Some t1 , Some t2 =>
              if t1 ?[ Rty ts ] t2 then
                typ2_match (fun _ => option subst) ts t
                           (fun d r =>
                              match exprUnify' us vs n s e1 e2 t1 with
                                | None => None
                                | Some s' =>
                                  exprUnify' us vs n s' e1' e2' d
                              end)
                           None
              else
                None
            | _ , _ => None
          end
        | Abs t1 e1 , Abs t2 e2 =>
          (* t1 = t2 since both terms have the same type *)
          typ2_match (F := Fun) (fun _ => _) ts t
                     (fun _ t =>
                        exprUnify' us (t1 :: vs) (S n) s e1 e2 t)
                     None
        | _ , _ => None
      end%bool.

  End nested.

  Section exprUnify.

    (** Delaying the recursion is probably important **)
    Fixpoint exprUnify (fuel : nat)
             (ts : list Type) (us vs : tenv typ) (under : nat) (s : subst)
             (e1 e2 : expr typ func) (t : typ) : option subst :=
      match fuel with
        | 0 => None
        | S fuel =>
          exprUnify' ts (fun tus tvs => exprUnify fuel ts tus tvs)
                     us vs under s e1 e2 t
      end.
  End exprUnify.

  Existing Instance SubstUpdate_subst.
  Existing Instance SubstOk_subst.

  Definition unify_sound_ind
    (unify : forall ts (us vs : tenv typ) (under : nat) (s : subst)
                    (l r : expr typ func)
                    (t : typ), option subst) : Prop :=
    forall tu tv e1 e2 s s' t tv',
      unify (@nil Type) tu (tv' ++ tv) (length tv') s e1 e2 t = Some s' ->
      WellFormed_subst (expr := expr typ func) s ->
      WellFormed_subst (expr := expr typ func) s' /\
      forall v1 v2 sD,
        exprD' nil tu (tv' ++ tv) t e1 = Some v1 ->
        exprD' nil tu (tv' ++ tv) t e2 = Some v2 ->
        substD tu tv s = Some sD ->
        exists sD',
             substD (expr := expr typ func) tu tv s' = Some sD'
          /\ forall us vs,
               sD' us vs ->
               sD us vs /\
               forall vs',
                 v1 us (hlist_app vs' vs) = v2 us (hlist_app vs' vs).

  Definition unify_sound := unify_sound_ind.

  Ltac forward_reason :=
    repeat match goal with
             | H : exists x, _ |- _ =>
               destruct H
             | H : _ /\ _ |- _ => destruct H
             | H' : ?X , H : ?X -> ?Y |- _ =>
               match type of X with
                 | Prop => specialize (H H')
               end
             | H : ?X -> ?Y |- _ =>
               match type of X with
                 | Prop =>
                   let H' := fresh in
                   assert (H' : X) by eauto ;
                   specialize (H H') ;
                   clear H'
               end
           end.

(*
  Lemma handle_set'
  : forall (e0 : expr func)
           (u : uvar) (s s' : subst),
      set u e0 s = Some s' ->
      WellFormed_subst s ->
      WellFormed_subst s' /\
      forall (tu : tenv typ) (tv : list typ)
             (t : typ) (tv' : list typ),
        (forall
            (v1 : _)
            (v2 : hlist (typD types nil) tu ->
                    hlist (typD types nil) (tv' ++ tv) -> typD types nil t)
            (sD : hlist (typD types nil) tu -> hlist (typD types nil) tv -> Prop),
            exprD' tu tv e0 t = Some v1 ->
            exprD' tu (tv' ++ tv) (UVar u) t = Some v2 ->
            substD tu tv s = Some sD ->
            exists
              sD' : hlist (typD types nil) tu -> hlist (typD types nil) tv -> Prop,
              substD tu tv s' = Some sD' /\
              (forall (us : hlist (typD types nil) tu)
                      (vs : hlist (typD types nil) tv),
                 sD' us vs ->
                 sD us vs /\
                 (forall vs' : hlist (typD types nil) tv',
                    v1 us vs = v2 us (hlist_app vs' vs)))).
  Proof.
    intros.
    eapply set_sound in H; eauto.
    forward_reason; split; eauto.
    intros.
    autorewrite with exprD_rw in *.
    forward; inv_all; subst.
    eapply nth_error_get_hlist_nth_Some in H5.
    forward_reason.
    simpl in *.
    specialize (H1 tu tv t _ _ H4 (eq_sym x) H2).
    forward_reason.
    eexists; split; eauto.
    intros. specialize (H5 _ _ H6).
    forward_reason.
    split; auto. intros.
    rewrite H3.
    match goal with
      | H : ?X = _ |- context [ ?Y ] =>
        change Y with X ; rewrite H
    end. clear.
    assert (forall X : typD types nil t,
              X = match
                x in (_ = t0)
                return match t0 with
                         | Some t1 => typD types nil t1
                         | None => unit
                       end
              with
                | eq_refl =>
                  match
                    eq_sym x in (_ = t0)
                    return
                    match t0 with
                      | Some x0 => typD types nil x0
                      | None => unit
                    end
                  with
                    | eq_refl => X
                  end
              end).
    { change (typD types nil t) with (match Some t with
                                        | Some t => typD types nil t
                                        | None => unit
                                      end).
      destruct x. reflexivity. }
    auto.
  Qed.

  Lemma handle_set
  : forall (e0 : expr func)
           (u : uvar) (s s' : subst),
      set u e0 s = Some s' ->
      WellFormed_subst s ->
      WellFormed_subst s' /\
      forall (tu : tenv typ) (tv : list typ)
             (t : typ) (tv' : list typ) (e : expr func),
        lower 0 (length tv') e = Some e0 ->
        (forall
            (v1
               v2 : hlist (typD types nil) tu ->
                    hlist (typD types nil) (tv' ++ tv) -> typD types nil t)
            (sD : hlist (typD types nil) tu -> hlist (typD types nil) tv -> Prop),
            exprD' tu (tv' ++ tv) e t = Some v1 ->
            exprD' tu (tv' ++ tv) (UVar u) t = Some v2 ->
            substD tu tv s = Some sD ->
            exists
              sD' : hlist (typD types nil) tu -> hlist (typD types nil) tv -> Prop,
              substD tu tv s' = Some sD' /\
              (forall (us : hlist (typD types nil) tu)
                      (vs : hlist (typD types nil) tv),
                 sD' us vs ->
                 sD us vs /\
                 (forall vs' : hlist (typD types nil) tv',
                    v1 us (hlist_app vs' vs) = v2 us (hlist_app vs' vs)))).
  Proof.
    intros.
    eapply set_sound in H; eauto.
    forward_reason; split; eauto.
    intros.
    autorewrite with exprD_rw in *.
    forward; inv_all; subst.
    eapply nth_error_get_hlist_nth_Some in H6.
    forward_reason.
    simpl in *.
    eapply  (@exprD'_lower _ _ RSym_func) with (us := tu) (vs := nil) (vs'' := tv) (t := t) in H2.
    simpl in *.
    match goal with
      | H : ?X = _ , H' : context [ ?Y ] |- _ =>
        change Y with X ; rewrite H in H'
    end.
    forward.
    specialize (H1 tu tv t _ _ H5 (eq_sym x) H2).
    forward_reason.
    eexists; split; eauto.
    intros. specialize (H7 _ _ H8).
    forward_reason.
    split; auto. intros.
    specialize (H6 us Hnil vs' vs).
    specialize (H4 us).
    simpl in *.
    rewrite <- H6 in *.
    Cases.rewrite_all_goal.
    clear - H9.
    match goal with
      | H : ?X = _ |- context [ ?Y ] =>
        change Y with X ; rewrite H
    end. clear.
    assert (forall X : typD types nil t,
              X = match
                x in (_ = t0)
                return match t0 with
                         | Some t1 => typD types nil t1
                         | None => unit
                       end
              with
                | eq_refl =>
                  match
                    eq_sym x in (_ = t0)
                    return
                    match t0 with
                      | Some x0 => typD types nil x0
                      | None => unit
                    end
                  with
                    | eq_refl => X
                  end
              end).
    { change (typD types nil t) with (match Some t with
                                        | Some t => typD types nil t
                                        | None => unit
                                      end).
      destruct x. reflexivity. }
    auto.
  Qed.

  Lemma handle_uvar
  : forall
        unify : tenv typ ->
                tenv typ ->
                nat -> subst -> expr func -> expr func -> typ -> option subst,
        unify_sound_ind unify ->
        forall (tu : tenv typ) (tv : list typ) e
               (u : uvar) (s s' : subst) (t : typ) (tv' : list typ),
          match lookup u s with
            | Some e2' =>
              unify tu (tv' ++ tv) (length tv') s e
                    (lift 0 (length tv') e2') t
            | None =>
              match lower 0 (length tv') e with
                | Some e1 => set u e1 s
                | None => None
              end
          end = Some s' ->
          WellFormed_subst s ->
          WellFormed_subst s' /\
          (forall
              (v1
                 v2 : hlist (typD types nil) tu ->
                      hlist (typD types nil) (tv' ++ tv) -> typD types nil t)
              (sD : hlist (typD types nil) tu -> hlist (typD types nil) tv -> Prop),
              exprD' tu (tv' ++ tv) e t = Some v1 ->
              exprD' tu (tv' ++ tv) (UVar u) t = Some v2 ->
              substD tu tv s = Some sD ->
              exists
                sD' : hlist (typD types nil) tu -> hlist (typD types nil) tv -> Prop,
                substD tu tv s' = Some sD' /\
                (forall (us : hlist (typD types nil) tu)
                        (vs : hlist (typD types nil) tv),
                   sD' us vs ->
                   sD us vs /\
                   (forall vs' : hlist (typD types nil) tv',
                      v1 us (hlist_app vs' vs) = v2 us (hlist_app vs' vs)))).
  Proof.
    intros.
    consider (lookup u s); intros.
    { eapply H in H2.
      forward_reason.
      split; eauto; intros.
      assert (exists v2',
                exprD' tu (tv' ++ tv) (lift 0 (length tv') e0) t = Some v2'
                /\ forall us vs vs',
                     sD us vs ->
                     v2 us (hlist_app vs' vs) = v2' us (hlist_app vs' vs)).
      { eapply substD_lookup in H0; eauto.
        forward_reason.
        simpl in *.
        autorewrite with exprD_rw in H5.
        forward. inv_all; subst.
        eapply nth_error_get_hlist_nth_Some in H8.
        simpl in *. forward_reason.
        generalize (@exprD'_lift types func _ tu nil tv' tv e0 x).
        simpl. rewrite H0. clear - x1 x2 H5 H7.
        intros; forward.
        assert (t = x) by congruence.
        subst.
        rewrite H.
        eexists; split; eauto.
        intros. rewrite H5.
        specialize (H0 us Hnil).
        simpl in *. rewrite H0. erewrite H7; eauto.
        generalize (x0 us vs).
        change (typD types nil x)
          with (match Some x with
                  | Some x => typD types nil x
                  | None => unit
                end).
        clear.
        destruct x2. uip_all. reflexivity. }
      forward_reason.
      specialize (H3 _ _ _ H4 H7 H6).
      forward_reason.
      eexists; split; eauto.
      intros. specialize (H9 _ _ H10).
      forward_reason. split; intros; eauto.
      rewrite H11. rewrite H8; eauto. }
    { forward. eapply handle_set in H3; intuition eauto. }
  Qed.

  Lemma handle_uvar'
  : forall
        unify : tenv typ ->
                tenv typ ->
                nat -> subst -> expr func -> expr func -> typ -> option subst,
        unify_sound_ind unify ->
        forall (tu : tenv typ) (tv : list typ) e
               (u : uvar) (s s' : subst) (t : typ) (tv' : list typ),
          match lookup u s with
            | Some e2' =>
              unify tu (tv' ++ tv) (length tv') s
                    (lift 0 (length tv') e2') e t
            | None =>
              match lower 0 (length tv') e with
                | Some e1 => set u e1 s
                | None => None
              end
          end = Some s' ->
          WellFormed_subst s ->
          WellFormed_subst s' /\
          (forall
              (v1
                 v2 : hlist (typD types nil) tu ->
                      hlist (typD types nil) (tv' ++ tv) -> typD types nil t)
              (sD : hlist (typD types nil) tu -> hlist (typD types nil) tv -> Prop),
              exprD' tu (tv' ++ tv) (UVar u) t = Some v1 ->
              exprD' tu (tv' ++ tv) e t = Some v2 ->
              substD tu tv s = Some sD ->
              exists
                sD' : hlist (typD types nil) tu -> hlist (typD types nil) tv -> Prop,
                substD tu tv s' = Some sD' /\
                (forall (us : hlist (typD types nil) tu)
                        (vs : hlist (typD types nil) tv),
                   sD' us vs ->
                   sD us vs /\
                   (forall vs' : hlist (typD types nil) tv',
                      v1 us (hlist_app vs' vs) = v2 us (hlist_app vs' vs)))).
  Proof.
    intros.
    consider (lookup u s); intros.
    { eapply H in H2.
      forward_reason.
      split; eauto; intros.
      assert (exists v2',
                exprD' tu (tv' ++ tv) (lift 0 (length tv') e0) t = Some v2'
                /\ forall us vs vs',
                     sD us vs ->
                     v1 us (hlist_app vs' vs) = v2' us (hlist_app vs' vs)).
      { eapply substD_lookup in H0; eauto.
        forward_reason.
        simpl in *.
        autorewrite with exprD_rw in H4.
        forward. inv_all; subst.
        eapply nth_error_get_hlist_nth_Some in H8.
        simpl in *. forward_reason.
        generalize (@exprD'_lift types func _ tu nil tv' tv e0 x).
        simpl. rewrite H0. clear - x1 x2 H4 H7.
        intros; forward.
        assert (t = x) by congruence.
        subst.
        rewrite H.
        eexists; split; eauto.
        intros.
        specialize (H0 us Hnil).
        simpl in *. rewrite H0.
        specialize (H7 _ _ H1).
        rewrite H4.
        match goal with
          | H : ?X = _ |- context [ ?Y ] =>
            change Y with X ; rewrite H
        end.
        clear.
        generalize (x0 us vs).
        change (typD types nil x)
          with (match Some x with
                  | Some x => typD types nil x
                  | None => unit
                end).
        clear.
        destruct x2. uip_all. reflexivity. }
      forward_reason.
      specialize (H3 _ _ _ H7 H5 H6).
      forward_reason.
      eexists; split; eauto.
      intros. specialize (H9 _ _ H10).
      forward_reason. split; intros; eauto.
      rewrite H8; eauto. }
    { forward. eapply handle_set in H3; intuition eauto.
      specialize (H5 _ _ _ _ _ H2 _ _ _ H6 H3 H7).
      forward_reason. eexists; split; eauto.
      intros. specialize (H8 _ _ H9). forward_reason; split; eauto. }
  Qed.

(*
  Lemma WellTyped_from_subst : forall tu tv tv' s e t u,
    WellFormed_subst s ->
    WellTyped_subst tu tv s ->
    WellTyped_expr tu (tv' ++ tv) (UVar u) t ->
    lookup u s = Some e ->
    WellTyped_expr tu (tv' ++ tv) (lift 0 (length tv') e) t.
  Proof.
    intros.
    rewrite WellTyped_expr_UVar in H1.
    eapply WellTyped_lookup in H0; eauto.
    destruct H0 as [ ? [ ? ? ] ].
    simpl in H3.
    etransitivity.
    eapply (typeof_expr_lift _ tu nil tv' tv e).
    rewrite H1 in *. inv_all; subst.
    simpl.
    destruct H3. simpl in *.
    eapply ExprD3.EXPR_DENOTE_core.exprD'_typeof in H0.
    assumption.
  Qed.

  Lemma exprD_from_subst : forall us vs vs' s e u t,
    WellFormed_subst s ->
    substD us vs s ->
    lookup u s = Some e ->
    nth_error (typeof_env us) u = Some t ->
    exprD us (vs' ++ vs) (UVar u) t =
    exprD us (vs' ++ vs) (lift 0 (length vs') e) t.
  Proof.
    intros.
    rewrite exprD_UVar.
    unfold lookupAs.
    generalize H1.
    eapply substD_lookup in H1; eauto.
    destruct H1. intuition.
    rewrite nth_error_typeof_env in *.
    rewrite H4 in *. destruct x; inv_all; subst. simpl in *.
    rewrite typ_cast_typ_refl.
    symmetry. etransitivity. eapply (exprD_lift _ us nil vs' vs).
    eapply H5.
  Qed.

  Lemma nth_error_from_WellTyped_UVar : forall tu tv u us t,
    WellTyped_expr tu tv (UVar u) t ->
    WellTyped_env (types := types) tu us ->
    nth_error (typeof_env us) u = Some t.
  Proof.
    intros.
    rewrite WellTyped_expr_UVar in *.
    rewrite WellTyped_env_typeof_env in *. subst. auto.
  Qed.
*)
*)

  Lemma exprUnify'_sound
  : forall unify,
      unify_sound_ind unify ->
      unify_sound_ind (fun ts => exprUnify' ts (unify ts)).
  Proof.
(*
    Opaque rel_dec.
    red. induction e1; simpl; intros.
    { destruct e2; try congruence; eauto using handle_uvar.
      { consider (EqNat.beq_nat v v0); intros; try congruence.
        inv_all; subst. intuition.
        eexists; split; eauto. intuition.
        congruence. } }
    { destruct e2; try congruence; eauto using handle_uvar.
      { consider (sym_eqb f f0); try congruence; intros.
        destruct b; try congruence. inv_all; subst.
        generalize (@sym_eqbOk _ _ _ _ RSymOk_func f f0).
        rewrite H0. intros; subst. intuition.
        eexists; split; eauto. intuition. congruence. } }
    { destruct e2; try congruence; eauto using handle_uvar.
      { forward. forward_reason. subst.
        specialize (IHe1_1 e2_1 s s0 (tyArr t4 t5) tv').
        specialize (IHe1_2 e2_2 s0 s' t4 tv').
        unfold WellTyped_expr in *.
        forward_reason.
        split; eauto. intros.
        autorewrite with exprD_rw in *.
        repeat match goal with
                 | H : _ |- _ => rewrite H in *
               end.
        forward. inv_all; subst.
        specialize (H13 _ _ _ eq_refl eq_refl eq_refl).
        forward_reason.
        specialize (H15 _ _ _ eq_refl eq_refl H9).
        forward_reason.
        eexists; split; eauto. intros.
        specialize (H15 _ _ H16). forward_reason.
        specialize (H13 _ _ H15); forward_reason.
        split; eauto. intros.
        destruct x. Cases.rewrite_all_goal. reflexivity. } }
    { destruct e2; try congruence; eauto using handle_uvar.
      { forward. subst.
        specialize (IHe1 e2 s s' t3 (t :: tv')). simpl in *.
        forward_reason.
        split; eauto; intros.
        autorewrite with exprD_rw in *. forward.
        inv_all; subst. subst.
        specialize (H9 _ _ _ eq_refl H7 H6).
        forward_reason.
        eexists; split; eauto. intros. forward_reason.
        specialize (H5 _ _ H8).
        intuition.
        eapply functional_extensionality; intros.
        apply (H10 (Hcons x0 vs')). } }
    { destruct e2; eauto using handle_uvar'.
      { consider (EqNat.beq_nat u u0); intros; inv_all; subst.
        { split; eauto; intros.
          autorewrite with exprD_rw in *.
          forward; inv_all; subst.
          eexists; split; eauto. }
        { consider (lookup u s); consider (lookup u0 s); intros.
          { eapply H in H4.
            forward_reason.
            split; eauto. intros.
            assert (exprD' tu (tv' ++ tv) (lift 0 (length tv') e0) t = Some v1) by admit.
            assert (exprD' tu (tv' ++ tv) (lift 0 (length tv') e) t = Some v2) by admit.
            specialize (H5 _ _ _ H9 H10 H8).
            eauto. }
          { clear H2. eapply handle_set' in H4; eauto.
            forward_reason; split; eauto. intros.
            eapply substD_lookup in H3; eauto.
            forward_reason.
            simpl in *.
            autorewrite with exprD_rw in H5.
            forward; inv_all; subst.
            eapply nth_error_get_hlist_nth_Some in H9.
            simpl in H9. forward_reason.
            assert (x = t) by congruence. subst.
            specialize (H4 _ _ _ _ _ _ _ H3 H6 H7).
            forward_reason.
            eexists; split; eauto.
            intros. specialize (H9 _ _ H10).
            forward_reason. split; eauto.
            intros.
            rewrite H5. rewrite <- H11.
            rewrite (H8 _ vs); eauto.
            clear.
            generalize (x0 us vs).
            change (typD types nil t)
              with (match Some t with
                      | Some t => typD types nil t
                      | None => unit
                    end).
            destruct x2. uip_all. reflexivity. }
          { clear H3. rename H2 into H3.
            eapply handle_set' in H4; eauto.
            forward_reason; split; eauto. intros.
            eapply substD_lookup in H3; eauto.
            forward_reason.
            simpl in *.
            autorewrite with exprD_rw in H6.
            forward; inv_all; subst.
            eapply nth_error_get_hlist_nth_Some in H9.
            simpl in H9. forward_reason.
            assert (x = t) by congruence. subst.
            specialize (H4 _ _ _ _ _ _ _ H3 H5 H7).
            forward_reason.
            eexists; split; eauto.
            intros. specialize (H9 _ _ H10).
            forward_reason. split; eauto.
            intros.
            rewrite H6. rewrite <- H11.
            rewrite (H8 _ vs); eauto.
            clear.
            generalize (x0 us vs).
            change (typD types nil t)
              with (match Some t with
                      | Some t => typD types nil t
                      | None => unit
                    end).
            destruct x2. uip_all. reflexivity. }
          { consider (set u (UVar u0) s); intros; inv_all; subst.
            { eapply handle_uvar'; eauto.
              rewrite H3. rewrite lower_lower'. simpl. assumption. }
            { eapply handle_uvar; eauto.
              rewrite H2. rewrite lower_lower'. simpl. assumption. } } } } }
*)
  Admitted.

  Theorem exprUnify_sound : forall fuel, unify_sound (exprUnify fuel).
  Proof.
    induction fuel; simpl; intros; try congruence.
    eapply exprUnify'_sound. eassumption.
  Qed.

End typed.
