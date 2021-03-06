Require Import MirrorCore.TypesI.
Require Import MirrorCore.Views.FuncView.
Require Import MirrorCore.Views.Ptrns.
Require Import MirrorCore.Views.TypeView.
Require Import MirrorCore.MTypes.ModularTypes.

Require Import ExtLib.Core.RelDec.
Require Import ExtLib.Data.POption.

Require Import Coq.Strings.String.

Set Implicit Arguments.
Set Strict Implicit.

Universe T.

Inductive base_typ : nat -> (Type@{T}) :=
| tNat : base_typ 0
| tString : base_typ 0
| tBool : base_typ 0
| tProp : base_typ 0.

Definition base_typ_dec {n} (a : base_typ n) : forall b, {a = b} + {a <> b}.
  refine(
    match a as a in base_typ n
          return forall b : base_typ n, {a = b} + {a <> b}
    with
    | tNat =>
      fun b =>
        match b as b in base_typ 0 return {tNat = b} + {tNat <> b} with
        | tNat => left eq_refl
        | _ => right (fun pf => _)
        end
    | tString =>
      fun b =>
        match b as b in base_typ 0 return {tString = b} + {tString <> b} with
        | tString => left eq_refl
        | _ => right (fun pf => _)
        end
    | tBool =>
      fun b =>
        match b as b in base_typ 0 return {tBool = b} + {tBool <> b} with
        | tBool => left eq_refl
        | _ => right (fun pf => _)
        end
    | tProp =>
      fun b =>
        match b as b in base_typ 0 return {tProp = b} + {tProp <> b} with
        | tProp => left eq_refl
        | _ => right (fun pf => _)
        end
    end);  clear -pf; inversion pf.
Defined.

Definition base_typD {n} (t : base_typ n) : type_for_arity n :=
  match t with
  | tNat => nat
  | tString => string
  | tBool => bool
  | tProp => Prop
  end.

Section DepMatch_base_typ.
  Context {typ : Type}.
  Context {RType_typ : RType typ}.
  Context {FV : PartialView typ (base_typ 0)}.
  Context {FVOk : TypeViewOk typD (base_typD (n := 0)) FV}. 

  Definition string_match (F : typ -> Type) (x : typ) :
    F (f_insert tString) -> (unit -> F x) -> F x :=
    match f_view x as Z return f_view x = Z -> F (f_insert tString) -> (unit -> F x) -> F x
    with
    | pSome v => 
      match v as y in base_typ 0 return f_view x = pSome y -> 
                                        F (f_insert tString) -> 
                                        (unit -> F x) -> F x with
      | tString => 
        fun pf X _ =>
          match (match @pv_ok _ _ _ _ FVOk x tString with | conj A _ => A end) pf 
                in _ = Z 
                return F Z with
          | eq_refl => X
          end
      | _ => fun _ _ X => X tt
      end 
    | pNone => fun _ _ X => X tt
    end eq_refl.

  Definition prop_match (F : typ -> Type) (x : typ) :
    F (f_insert tProp) -> (unit -> F x) -> F x :=
    match f_view x as Z return f_view x = Z -> F (f_insert tProp) -> (unit -> F x) -> F x
    with
    | pSome v => 
      match v as y in base_typ 0 return f_view x = pSome y -> 
                                        F (f_insert tProp) -> 
                                        (unit -> F x) -> F x with
      | tProp => 
        fun pf X _ =>
          match (match @pv_ok _ _ _ _ FVOk x tProp with | conj A _ => A end) pf 
                in _ = Z 
                return F Z with
          | eq_refl => X
          end
      | _ => fun _ _ X => X tt
      end 
    | pNone => fun _ _ X => X tt
    end eq_refl.


End DepMatch_base_typ.

Section TypeView_base_type.
  Context {typ : Type}.
  Context {FV : PartialView typ (base_typ 0)}.

  Definition tyNat := f_insert tNat.
  Definition tyBool := f_insert tBool.
  Definition tyString := f_insert tString.
  Definition tyProp := f_insert tProp.

  Definition ptrn_tyNat : ptrn (base_typ 0) (base_typ 0) :=
    fun f U good bad =>
      match f with
      | tNat => good f
      | _ => bad f
      end.

  Definition ptrn_tyBool : ptrn (base_typ 0) (base_typ 0) :=
    fun f U good bad =>
      match f with
      | tBool => good f
      | _ => bad f
      end.

  Definition ptrn_tyString : ptrn (base_typ 0) (base_typ 0) :=
    fun f U good bad =>
      match f with
      | tString => good f
      | _ => bad f
      end.

  Definition ptrn_tyProp : ptrn (base_typ 0) (base_typ 0) :=
    fun f U good bad =>
      match f with
      | tProp => good f
      | _ => bad f
      end.

  Global Instance ptrn_tyNat_ok  : ptrn_ok ptrn_tyNat.
  Proof.
    red; intros.
    unfold ptrn_tyNat.
    destruct x; simpl.
    { left. exists tNat. unfold Succeeds. reflexivity. }
    { right; unfold Fails; reflexivity. }
    { right; unfold Fails; reflexivity. }
    { right; unfold Fails; reflexivity. }
  Qed.

  Global Instance ptrn_tyBool_ok  : ptrn_ok ptrn_tyBool.
  Proof.
    red; intros.
    unfold ptrn_tyBool.
    destruct x; simpl.
    { right; unfold Fails; reflexivity. }
    { right; unfold Fails; reflexivity. }
    { left. exists tBool. unfold Succeeds. reflexivity. }
    { right; unfold Fails; reflexivity. }
  Qed.

  Global Instance ptrn_tyString_ok  : ptrn_ok ptrn_tyString.
  Proof.
    red; intros.
    unfold ptrn_tyString.
    destruct x; simpl.
    { right; unfold Fails; reflexivity. }
    { left. exists tString. unfold Succeeds. reflexivity. }
    { right; unfold Fails; reflexivity. }
    { right; unfold Fails; reflexivity. }
  Qed.

  Global Instance ptrn_tyProp_ok  : ptrn_ok ptrn_tyProp.
  Proof.
    red; intros.
    unfold ptrn_tyProp.
    destruct x; simpl.
    { right; unfold Fails; reflexivity. }
    { right; unfold Fails; reflexivity. }
    { right; unfold Fails; reflexivity. }
    { left. exists tProp. unfold Succeeds. reflexivity. }
  Qed.

End TypeView_base_type.

Section RelDec_base_type.

  Global Instance RelDec_base_typ (x : nat) : RelDec (@eq (base_typ x)) := {
    rel_dec a b :=
      match base_typ_dec a b with
      | left _ => true
      | right _ => false
      end
  }.

  Global Instance RelDecOk_base_typ (x : nat) : RelDec_Correct (RelDec_base_typ x).
  Proof.
    split; intros.
    unfold rel_dec; simpl.
    remember (base_typ_dec x0 y).
    destruct s; subst; intuition.
  Qed.
  
End RelDec_base_type.

Section TSym_base_type.

  Global Instance TSym_base_typ : TSym base_typ := {
    symbolD n := base_typD (n := n);
    symbol_dec n := base_typ_dec (n := n)    
  }.

End TSym_base_type.