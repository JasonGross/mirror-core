Require Import List.
Require Import ExtLib.Core.RelDec.
Require Import ExtLib.Data.ListNth.
Require Import ExtLib.Tactics.Consider.
Require Import ExtLib.Tactics.Injection.
Require Import ExtLib.Tactics.EqDep.
Require Import MirrorCore.Prover.
Require Import MirrorCore.EnvI.
Require Import MirrorCore.Subst.
Require Import MirrorCore.Ext.Types.
Require Import MirrorCore.Ext.ExprCore.
Require Import MirrorCore.Ext.ExprT.
Require Import MirrorCore.Ext.ExprD.
Require Import MirrorCore.Ext.ExprLift.

(** TODO **)
Require Import FunctionalExtensionality.

Set Implicit Arguments.
Set Strict Implicit.

Section typed.
  Variable subst : Type.
  Variable types : Types.types.
  Variable funcs : functions types.
  Variable Subst_subst : Subst subst expr.
  Variable SubstOk_subst : SubstOk (Expr_expr funcs) Subst_subst.

  Section nested.
    Variable tfs : tfunctions.

    (** n is the number of binders that we have gone under **)
  Variable exprUnify : forall (us vs : tenv typ) (under : nat) (s : subst) (l r : expr), typ -> option subst.

  Fixpoint exprUnify' (us vs : tenv typ) (n : nat) (s : subst) (e1 e2 : expr) (t : typ) {struct e1}
  : option subst.
  refine (
    match e1 , e2 with
      | UVar u1 , UVar u2 =>
        if EqNat.beq_nat u1 u2 then Some s
        else
          match Subst.set u1 (UVar u2) s with
            | None => Subst.set u2 (UVar u1) s
            | x => x
          end
      | UVar u1 , _ =>
        match Subst.lookup u1 s with
          | None =>
            match lower 0 n e2 with
              | None => None
              | Some e2 => Subst.set u1 e2 s
            end
          | Some e1' => exprUnify us vs n s (lift 0 n e1') e2 t
        end
      | _ , UVar u2 =>
        match Subst.lookup u2 s with
          | None =>
            match lower 0 n e1 with
              | None => None
              | Some e1 => Subst.set u2 e1 s
            end
          | Some e2' => exprUnify us vs n s e1 (lift 0 n e2') t
        end
      | Var v1 , Var v2 =>
        if EqNat.beq_nat v1 v2 then Some s else None
      | Func f1 ts1 , Func f2 ts2 =>
        if EqNat.beq_nat f1 f2 && ts1 ?[ eq ] ts2 then Some s else None
      | App e1 e1' , App e2 e2' =>
        match typeof_expr tfs us vs e1 , typeof_expr tfs us vs e2 with
          | Some (tvArr l r) , Some (tvArr l' r') =>
            if l ?[ eq ] l' && r ?[ eq ] r' && t ?[ eq ] r then
              match exprUnify' us vs n s e1 e2 (tvArr l t) with
                | None => None
                | Some s' =>
                  exprUnify' us vs n s' e1' e2' l
              end
            else
              None
          | _ , _ => None
        end
      | Abs t1 e1 , Abs t2 e2 =>
        (* t1 = t2 since both terms have the same type *)
        match t with
          | tvArr _ t =>
            exprUnify' us (t1 :: vs) (S n) s e1 e2 t
          | _ => None
        end
      | Not e1 , Not e2 =>
        exprUnify' us vs n s e1 e2 tvProp
      | Equal t' e1 e2 , Equal t'' e1' e2' =>
        if t' ?[ eq ] t'' then
          match exprUnify' us vs n s e1 e1' t' with
            | None => None
            | Some s' => exprUnify' us vs n s' e2 e2' t'
          end
        else None
      | _ , _ => None
    end)%bool.
  Defined.
  End nested.

  Section exprUnify.
    Variable tfs : tfunctions.

    Fixpoint exprUnify (fuel : nat) (us vs : tenv typ) (under : nat) (s : subst) (e1 e2 : expr) (t : typ) 
    : option subst :=
      match fuel with
        | 0 => None
        | S fuel =>
          exprUnify' tfs (exprUnify fuel) us vs under s e1 e2 t
      end.
  End exprUnify.

  Definition unify_sound_ind
    (unify : forall (us vs : tenv typ) (under : nat) (s : subst) (l r : expr)
                    (t : typ), option subst) : Prop :=
    forall tu tv e1 e2 s s' t tv',
      WellTyped_expr (typeof_funcs funcs) tu (tv' ++ tv) e1 t ->
      WellTyped_expr (typeof_funcs funcs) tu (tv' ++ tv) e2 t ->
      WellTyped_subst (SubstOk := SubstOk_subst) tu tv s ->
      unify tu (tv' ++ tv) (length tv') s e1 e2 t = Some s' ->
         WellTyped_subst (SubstOk := SubstOk_subst) tu tv s'
      /\ (forall u v,
            WellTyped_env tu u ->
            WellTyped_env tv v ->
            substD (SubstOk := SubstOk_subst) u v s' ->
               substD (SubstOk := SubstOk_subst) u v s
            /\ forall v',
                 WellTyped_env tv' v' ->
                 exprD funcs u (v' ++ v) e1 t = exprD funcs u (v' ++ v) e2 t).

  Definition unify_sound := unify_sound_ind.

  Lemma handle_set : forall
    (unify : tenv typ -> tenv typ -> nat -> subst ->
             expr -> expr -> typ -> option subst),
    unify_sound_ind unify ->
    forall (tu : tenv typ) (tv : list typ) (u : uvar)
           (s s' : subst) (t : typ) (tv' : list typ),
      WellTyped_expr (@typeof_funcs types funcs) tu (tv' ++ tv) (UVar u) t ->
      @WellTyped_subst subst expr typ (typD types) (@Expr_expr types funcs)
                       Subst_subst SubstOk_subst tu tv s ->
      forall e e' : expr,
        WellTyped_expr (@typeof_funcs types funcs) tu (tv' ++ tv) e t ->
        lower 0 (length tv') e = Some e' ->
        @set subst expr Subst_subst u e' s = @Some subst s' ->
        @WellTyped_subst subst expr typ (typD types) (@Expr_expr types funcs)
                         Subst_subst SubstOk_subst tu tv s' /\
        (forall u0 v : @env typ (typD types),
           @WellTyped_env types tu u0 ->
           @WellTyped_env types tv v ->
           @substD subst expr typ (typD types) (@Expr_expr types funcs) Subst_subst
                   SubstOk_subst u0 v s' ->
           @substD subst expr typ (typD types) (@Expr_expr types funcs) Subst_subst
                   SubstOk_subst u0 v s /\
           (forall v' : @env typ (typD types),
              @WellTyped_env types tv' v' ->
              @exprD types funcs u0 (v' ++ v) (UVar u) t =
              @exprD types funcs u0 (v' ++ v) e t)).
  Proof.
    intros.
    split; eauto using WellTyped_subst_set. intros.
    generalize H3. intro. eapply substD_set in H7; eauto.
    destruct H7; split; auto. intros.
    rewrite WellTyped_expr_UVar in H0.
    eapply WellTyped_env_typeof_env in H5. subst.
    unfold typeof_env in H0. rewrite nth_error_map in H0.
    autorewrite with exprD_rw. unfold lookupAs.
    destruct (nth_error u0 u); try congruence.
    specialize (H9 _ eq_refl).
    inv_all; subst.
    generalize (exprD_lower funcs u0 nil v' v e). simpl.
    cutrewrite (length v' = length tv'). intro X; eapply X in H8.
    etransitivity. 2: symmetry; eassumption. destruct s0; simpl.
    rewrite typ_cast_typ_refl. eauto.
    eapply WellTyped_env_typeof_env in H10. subst.
    rewrite typeof_env_length. auto.
  Qed.

  Lemma handle_uvar : forall
     unify : tenv typ ->
             tenv typ -> nat -> subst -> expr -> expr -> typ -> option subst,
   unify_sound_ind unify ->
   forall (tu : tenv typ) (tv : list typ) (u : uvar)
     (s s' : subst) (t : typ) (tv' : list typ),
   WellTyped_expr (@typeof_funcs types funcs) tu (tv' ++ tv) (UVar u) t ->
   @WellTyped_subst subst expr typ (typD types) (@Expr_expr types funcs)
     Subst_subst SubstOk_subst tu tv s ->
   forall e : expr,
   WellTyped_expr (@typeof_funcs types funcs) tu (tv' ++ tv) e t ->
   match @lookup subst expr Subst_subst u s with
   | Some e2' =>
       unify tu (tv' ++ tv) (@length typ tv') s e
         (lift 0 (@length typ tv') e2') t
   | None =>
       match lower 0 (@length typ tv') e with
       | Some e1 => @set subst expr Subst_subst u e1 s
       | None => @None subst
       end
   end = @Some subst s' ->
   @WellTyped_subst subst expr typ (typD types) (@Expr_expr types funcs)
     Subst_subst SubstOk_subst tu tv s' /\
   (forall u0 v : @env typ (typD types),
    @WellTyped_env types tu u0 ->
    @WellTyped_env types tv v ->
    @substD subst expr typ (typD types) (@Expr_expr types funcs) Subst_subst
      SubstOk_subst u0 v s' ->
    @substD subst expr typ (typD types) (@Expr_expr types funcs) Subst_subst
      SubstOk_subst u0 v s /\
    (forall v' : @env typ (typD types),
     @WellTyped_env types tv' v' ->
     @exprD types funcs u0 (v' ++ v) e t =
     @exprD types funcs u0 (v' ++ v) (UVar u) t)).
  Proof.
    intros.
    consider (lookup u s); intros.
    { eapply H in H4; eauto using WellTyped_subst_lookup.
      { destruct H4; split; auto.
        intros. specialize (H5 _ _ H6 H7 H8). destruct H5; split; auto.
        intros. specialize (H9 _ H10).
        autorewrite with exprD_rw.
        unfold lookupAs.
        eapply substD_lookup in H3; eauto.
        destruct H3. destruct x. destruct H3. simpl in *. rewrite H3.
        assert (x = t).
        { rewrite WellTyped_expr_UVar in H0.
          eapply WellTyped_env_typeof_env in H6. subst.
          unfold typeof_env in H0.
          rewrite nth_error_map in H0. rewrite H3 in *. inv_all.
          simpl in *. auto. }
        subst. rewrite typ_cast_typ_refl. etransitivity. eapply H9.
        generalize (@exprD_lift _ funcs u0 nil v' v e0 t). simpl.
        cutrewrite (length v' = length tv').
        { intro X. etransitivity. eapply X. auto. }
        { eapply WellTyped_env_typeof_env in H10. subst. rewrite typeof_env_length. auto. } }
      { eapply WellTyped_subst_lookup in H3. 2: eauto. 2: eauto.
        unfold WellTyped_expr.
        generalize (typeof_expr_lift (typeof_funcs funcs) tu nil tv' tv e0); simpl.
        intros. etransitivity; eassumption. } }
    { match goal with
        | _ : match ?X with _ => _ end = _ |- _ =>
          consider X; try congruence; intros
      end.
      eapply handle_set in H5; eauto. intuition.
      destruct (H7 _ _ H5 H8 H9); auto.
      destruct (H7 _ _ H5 H8 H9); auto.
      symmetry; eauto. }
  Qed.

  Lemma handle_uvar2 : forall
     unify : tenv typ ->
             tenv typ -> nat -> subst -> expr -> expr -> typ -> option subst,
   unify_sound_ind unify ->
   forall (tu : tenv typ) (tv : list typ) (u : uvar)
     (s s' : subst) (t : typ) (tv' : list typ),
   WellTyped_expr (@typeof_funcs types funcs) tu (tv' ++ tv) (UVar u) t ->
   @WellTyped_subst subst expr typ (typD types) (@Expr_expr types funcs)
     Subst_subst SubstOk_subst tu tv s ->
   forall e : expr,
   WellTyped_expr (@typeof_funcs types funcs) tu (tv' ++ tv) e t ->
   match @lookup subst expr Subst_subst u s with
   | Some e2' =>
       unify tu (tv' ++ tv) (@length typ tv') s
         (lift 0 (@length typ tv') e2') e t
   | None =>
       match lower 0 (@length typ tv') e with
       | Some e1 => @set subst expr Subst_subst u e1 s
       | None => @None subst
       end
   end = @Some subst s' ->
   @WellTyped_subst subst expr typ (typD types) (@Expr_expr types funcs)
     Subst_subst SubstOk_subst tu tv s' /\
   (forall u0 v : @env typ (typD types),
    @WellTyped_env types tu u0 ->
    @WellTyped_env types tv v ->
    @substD subst expr typ (typD types) (@Expr_expr types funcs) Subst_subst
      SubstOk_subst u0 v s' ->
    @substD subst expr typ (typD types) (@Expr_expr types funcs) Subst_subst
      SubstOk_subst u0 v s /\
    (forall v' : @env typ (typD types),
     @WellTyped_env types tv' v' ->
     @exprD types funcs u0 (v' ++ v) (UVar u) t =
     @exprD types funcs u0 (v' ++ v) e t)).
  Proof.
    intros.
    consider (lookup u s); intros.
    { eapply H in H4; eauto using WellTyped_subst_lookup.
      { destruct H4; split; auto.
        intros. specialize (H5 _ _ H6 H7 H8). destruct H5; split; auto.
        intros. specialize (H9 _ H10).
        autorewrite with exprD_rw.
        unfold lookupAs.
        eapply substD_lookup in H3; eauto.
        destruct H3. destruct x. destruct H3. simpl in *. rewrite H3.
        assert (x = t).
        { rewrite WellTyped_expr_UVar in H0.
          eapply WellTyped_env_typeof_env in H6. subst.
          unfold typeof_env in H0.
          rewrite nth_error_map in H0. rewrite H3 in *. inv_all.
          simpl in *. auto. }
        subst. rewrite typ_cast_typ_refl. symmetry.  etransitivity. symmetry. eapply H9.
        generalize (@exprD_lift _ funcs u0 nil v' v e0 t). simpl.
        cutrewrite (length v' = length tv').
        { intro X. etransitivity. eapply X. auto. }
        { eapply WellTyped_env_typeof_env in H10. subst. rewrite typeof_env_length. auto. } }
      { eapply WellTyped_subst_lookup in H3. 2: eauto. 2: eauto.
        unfold WellTyped_expr.
        generalize (typeof_expr_lift (typeof_funcs funcs) tu nil tv' tv e0); simpl.
        intros. etransitivity; eassumption. } }
    { match goal with
        | _ : match ?X with _ => _ end = _ |- _ =>
          consider X; try congruence; intros
      end.
      eapply handle_set in H5; eauto. }
  Qed.

  Lemma exprUnify'_sound : forall unify,
                             unify_sound_ind unify ->
                             unify_sound_ind (exprUnify' (typeof_funcs funcs) unify).
  Proof.
    Opaque rel_dec.
    red. induction e1; simpl; intros.
    { destruct e2; try congruence; eauto using handle_uvar.
      { consider (EqNat.beq_nat v v0); intros; try congruence.
        inv_all; subst. intuition. } }
    { destruct e2; try congruence; eauto using handle_uvar.
      { consider (EqNat.beq_nat f f0 && l ?[ eq ] l0)%bool; try congruence; intros; subst.
        destruct H3; inv_all; subst.
        intuition. } }
    { destruct e2; try congruence; eauto using handle_uvar.
      { repeat match goal with
                 | H : match ?X with _ => _ end = _ |- _ =>
                   (consider X; try congruence); [ intros ]
                 | H : not (match ?X with _ => _ end = _) |- _ =>
                   (consider X; try congruence); [ intros ]
                 | H : _ /\ _ |- _ => destruct H
                 | H : not (Some _ = None) |- _ => clear H
               end.
        subst.
        eapply WellTyped_expr_App in H0.
        eapply WellTyped_expr_App in H1.
        do 2 destruct H0. do 2 destruct H1.
        unfold WellTyped_expr in *. rewrite H4 in *.
        repeat match goal with
                 | H : _ /\ _ |- _ => destruct H
                 | H : _ = _ , H' : _ = _ |- _ =>
                   match H with
                     | H' => fail 1
                     | _ => rewrite H in H'
                   end
                 | |- _ => progress (inv_all; subst)
               end.
        simpl in *.
        change typ_eqb with (@rel_dec _ (@eq typ) _) in *.
        consider (t4 ?[ eq ] x0); try congruence.
        consider (t4 ?[ eq ] x2); try congruence.
        intros; inv_all; subst. subst.
        eapply IHe1_1 in H8; try congruence; eauto.
        destruct H8.
        eapply IHe1_2 in H9; try congruence; eauto.
        split.
        { intuition. }
        { intros. destruct H9.
          specialize (H13 u v H8 H11 H12). destruct H13.
          specialize (H5 u v H8 H11 H13). intuition.
          assert (tu = typeof_env u) by (eapply WellTyped_env_typeof_env; assumption).
          assert (tv = typeof_env v) by (eapply WellTyped_env_typeof_env; assumption).
          assert (tv' = typeof_env v') by (eapply WellTyped_env_typeof_env; assumption).
          subst.
          autorewrite with exprD_rw.
          repeat rewrite typeof_env_app in *.
          repeat match goal with
                   | H : _ |- _ => rewrite H
                 end. reflexivity.
          eapply WellTyped_env_typeof_env; reflexivity.
          eapply WellTyped_env_typeof_env; reflexivity. } } }
    { destruct e2; try congruence; eauto using handle_uvar.
      { destruct t0; try congruence.
        specialize (IHe1 e2 s s' t0_2 (t :: tv')). simpl in *.
        eapply WellTyped_expr_Abs in H0. eapply WellTyped_expr_Abs in H1.
        repeat match goal with
                 | H : exists x, _ |- _ => destruct H
                 | H : _ /\ _ |- _ => destruct H
               end.
        inversion H0; clear H0; subst. inversion H1; clear H1; subst.
        destruct (IHe1 H5 H4 H2 H3); clear IHe1.
        split; auto.
        intros.
        assert (tu = typeof_env u) by (eapply WellTyped_env_typeof_env; assumption).
        assert (tv = typeof_env v) by (eapply WellTyped_env_typeof_env; assumption).
        specialize (H1 u v H6 H7 H8).
        intuition.
        autorewrite with exprD_rw.
        assert (tv' = typeof_env v') by (eapply WellTyped_env_typeof_env; assumption); subst.
        gen_refl.
        generalize (@typeof_expr_eq_exprD_False types funcs u t1 (v' ++ v) e1 x).
        generalize (@typeof_expr_eq_exprD_False types funcs u t1 (v' ++ v) e2 x).
        unfold typecheck_expr, WellTyped_expr in *.
        erewrite typeof_env_app. simpl in *.
        rewrite H5. rewrite H4.
        repeat rewrite rel_dec_eq_true by eauto with typeclass_instances.
        intros. unfold exprD in *. simpl in *. remember (split_env (v' ++ v)).
        destruct s0.
        simpl in *.
        repeat rewrite exprD'_Abs.
        rewrite typ_cast_typ_refl.
        specialize (H9 eq_refl). specialize (H10 eq_refl).
        destruct (@typeof_exprD _ _ _ _ _ _ H4).
        destruct (@typeof_exprD _ _ _ _ _ _ H5).
        assert (typeof_env v' ++ typeof_env v = x0).
        { rewrite <- typeof_env_app.
          generalize (@split_env_projT1 _ _ (v' ++ v)).
          rewrite <- Heqs0. simpl. intro. symmetry. exact H15. }
        subst.
        eapply typeof_exprD in H4. destruct H4.
        eapply typeof_exprD in H5; destruct H5.
        rewrite H4 in *. rewrite H5 in *.
        f_equal.
        eapply functional_extensionality; intros.
        inv_all; subst.
        specialize (H12 (existT _ t1 x4 :: v')). simpl in H12.
        rewrite <- Heqs0 in *. simpl in *.
        rewrite H5 in *. rewrite H4 in *.
        assert (WellTyped_env (t1 :: typeof_env v') (existT (typD types nil) t1 x4 :: v')).
        { constructor; auto. }
        apply H12 in H13. inv_all. auto. } }
    { destruct e2; eauto using handle_uvar2.
      { consider (EqNat.beq_nat u u0); intros; inv_all; subst.
        { intuition. }
        { consider (set u (UVar u0) s); intros; inv_all; subst.
          { eapply handle_set. 6: eassumption. eauto.
            eauto. eauto. eauto. rewrite lower_lower'. simpl. reflexivity. }
          { eapply handle_set in H5. 2: eassumption.
            2: eassumption. 3: eapply H0. 2: eauto.
            2: rewrite lower_lower'; reflexivity.
            split. intuition.
            intros. destruct H5.
            specialize (H9 _ _ H6 H7 H8). intuition.
            rewrite H11; eauto. } } } }
    { destruct e2; try congruence; eauto using handle_uvar.
      { consider (t ?[ eq ] t1); try congruence; intros; subst.
        consider (exprUnify' (typeof_funcs funcs) unify tu (tv' ++ tv)
                             (length tv') s e1_1 e2_1 t1); try congruence; intros.
        eapply WellTyped_expr_Equal in H1. eapply WellTyped_expr_Equal in H0.
        destruct H1 as [ ? [ ? ? ] ]. destruct H0 as [ ? [ ? ? ] ].
        subst.
        eapply IHe1_1 in H3; eauto. destruct H3.
        eapply IHe1_2 in H4; eauto. destruct H4.
        split; auto.
        intros.
        specialize (H9 u v H10 H11 H12). destruct H9.
        specialize (H3 u v H10 H11 H9). destruct H3.
        split; auto.
        intros.
        specialize (H14 _ H15). specialize (H13 _ H15).
        autorewrite with exprD_rw. rewrite H14. rewrite H13. reflexivity. } }
    { destruct e2; try congruence; eauto using handle_uvar.
      { eapply WellTyped_expr_Not in H1; eapply WellTyped_expr_Not in H0.
        destruct H0; destruct H1; subst. eapply IHe1 in H3; eauto.
        destruct H3; split; auto. intros.
        specialize (H3 _ _ H6 H7 H8). destruct H3; split; auto.
        intros. specialize (H9 _ H10).
        autorewrite with exprD_rw. rewrite H9. auto. } }
  Qed.

  Theorem exprUnify_sound : forall fuel, unify_sound (exprUnify (typeof_funcs funcs) fuel).
  Proof.
    induction fuel; simpl; intros; try congruence.
    eapply exprUnify'_sound. eassumption.
  Qed.

End typed.