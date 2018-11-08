Require Import bedrock2.Macros bedrock2.Syntax.
Require Import bedrock2.BasicC64Syntax bedrock2.BasicALU bedrock2.NotationsInConstr.

Import BinInt String List.ListNotations.
Local Open Scope string_scope. Local Open Scope Z_scope. Local Open Scope list_scope.
Local Existing Instance bedrock2.BasicC64Syntax.Basic_bopnames_params.
Local Coercion literal (z : Z) : expr := expr.literal z.
Local Coercion var (x : string) : expr := expr.var x.

Definition swap := ("swap", (["a";"b"], ([]:list varname), bedrock_func_body:(
  "t" = *(uint8_t*) "b";;
  *(uint8_t*) "b" = *(uint8_t*) "a";;
  *(uint8_t*) "a" = "t"
))).

Definition swap_swap := ("swap_swap", (("a"::"b"::nil), ([]:list varname), bedrock_func_body:(
  cmd.call [] "swap" [var "a"; var "b"];;
  cmd.call [] "swap" [var "a"; var "b"]
))).

Require Import bedrock2.Semantics bedrock2.BasicC64Semantics bedrock2.Map.
Require Import bedrock2.Map.Separation bedrock2.Map.SeparationLogic.
Require bedrock2.WeakestPrecondition bedrock2.WeakestPreconditionProperties.
(* Require bedrock2.WeakestPreconditionProperties. *)
Context (FIXME_MAP_OK : map.ok Semantics.mem).

Section WithT.
  Context {T : Type}.
  Fixpoint bindcmd (c : cmd) (k : cmd -> T) {struct c} : T :=
    match c with
    | cmd.cond e c1 c2 => bindcmd c1 (fun c1 => bindcmd c2 (fun c2 => let c := cmd.cond e c1 c2 in k c))
    | cmd.seq c1 c2 => bindcmd c1 (fun c1 => bindcmd c2 (fun c2 => let c := cmd.seq c1 c2 in k c))
    | cmd.while e c => bindcmd c (fun c => let c := c in k c)
    | c => let c := c in k c
    end.
End WithT.

(*
Lemma get_sep {key value} {map : map key value} (a:key) (v:value) R m (H : sep (ptsto a v) R m) : map.get m a = Some v.
Admitted.
Lemma put_sep {key value} {map : map key value} (k:key) (v1:value) (v2:value) R m :
  sep (ptsto k v1) R m -> sep (ptsto k v2) R (map.put m k v2).
Admitted.
Lemma split_combine n a b : split n (Semantics.combine n a b) = (a, b).
Admitted.
*)

Definition ptsto sz a v m := load sz m a = Some v.
Lemma load_sep sz a v R m (H : sep (ptsto sz a v) R m) : load sz m a = Some v.
  cbv [load ptsto] in *.
  revert H; revert R; revert v; revert a; revert m.
  generalize (BinIntDef.Z.to_nat sz) as n; clear sz.
  induction n.
  { intros; destruct H as (?&?&?&?&?); auto. }
  { intros.
    cbn [load_rec] in *.
    destruct H as (?&?&?&?&?).
    destruct (map.get x a) eqn:?; [|discriminate].
    { assert (map.get m a = Some b) by admit.
      rewrite H2.
      destruct (load_rec n x (word_succ a)) eqn:?; [|discriminate].
      { unshelve erewrite (_:load_rec n m (word_succ a) = Some w); [admit|].
        assumption. } } }
Admitted.

Lemma store_sep sz a v1 v2 R m (H : sep (ptsto sz a v1) R m)
      (post : _ -> Prop) (cont : forall m', sep (ptsto sz a v2) R m' -> post m') :
  exists m', store sz m a v2 = Some m' /\ post m'.
Admitted.

Local Notation "'need!' y 's.t.' Px 'let' x ':=' v 'using' pfPx 'in' pfP" :=
  (let x := v in ex_intro (fun y => Px /\ _) x (conj pfPx pfP))
  (right associativity, at level 200, pfPx at next level,
    format "'need!'  y  's.t.'  Px  '/' 'let'  x  ':='  v  'using'  pfPx  'in'  '/' pfP").
Local Notation "'need!' x 's.t.' Px 'let' x ':=' v 'using' pfPx 'in' pfP" :=
  (let x := v in ex_intro (fun x => Px /\ _) x (conj pfPx pfP))
  (only printing, right associativity, at level 200, pfPx at next level,
    format "'need!'  x  's.t.'  Px  '/' 'let'  x  ':='  v  'using'  pfPx  'in'  '/' pfP").
Local Notation "'have!' m1 's.t.' x : T 'using' 'store_sep' '...' 'in' pfP" :=
  (store_sep _ _ _ _ _ _ _ _ (fun m1 (x:T) => pfP))
  (only printing, right associativity, at level 200,
    format "'have!'  m1  's.t.'  x :  T  'using'  'store_sep'  '...'  'in'  pfP").

(*
Ltac intros_mem m Hm :=
  let m' := fresh in let Hm' := fresh in
  intros m' Hm'; clear m Hm; rename m' into m; rename Hm' into Hm.
Ltac t :=
  let m := lazymatch goal with m : @map.rep word byte mem |- _ => m end in
  let Hm := lazymatch goal with Hm : _ m |- _ => Hm end in
  let Tm := type of m in
  let Pm := lazymatch type of Hm with ?P m => P end in
  lazymatch goal with
  | |- let _ := _ in _ => intros
  | |- _ => progress copyprop
  | |- load ?sz ?m ?a = Some _
    => lazymatch type of Hm with context [ptsto sz a ?v]
    => refine (load_sep sz a v ?[frame] m ((?[sep]:@Lift1Prop.impl1 Tm Pm _) m Hm));
       eabstract (cancel; reflexivity) end
  | |- WeakestPrecondition.store ?sz ?m ?a ?v2 _
    => lazymatch type of Hm with context [ptsto sz a ?v1]
    => refine (store_sep sz a v1 v2 ?[frame] m ((?[sep]:@Lift1Prop.impl1 Tm Pm _) m Hm) _ ?[cont]); [ eabstract (cancel; reflexivity) | intros_mem m Hm ] end
  | |- ?G =>
    hnf;
    match goal with
    | H: G |- _ => exact H
    | _ => exact eq_refl
    | |- ex (fun x : ?T => ?Px /\ ?P) =>
      let y := fresh x in
      simple refine (let y : T := _ in
                     @ex_intro T (fun x => Px /\ P) y
                     (@conj (subst! y for x in Px) (subst! y for x in P) _ _));
      [ shelve | .. ]
    end
end.
*)

Tactic Notation "eabstract" tactic3(tac) :=
  let G := match goal with |- ?G => G end in
  let pf := lazymatch constr:(ltac:(tac) : G) with ?pf => pf end in
  abstract exact_no_check pf.

Ltac clear_all :=
  clear;
  repeat match reverse goal with
  | H :  _ |- _ => clear H
  | x := _ |- _ => clear x
  end.

Ltac copyprop :=
  repeat match reverse goal with
  | x := ?y |- ?G => is_var y; change x with y in *; clear x
  end.

Ltac refine_ex :=
  hnf;
  let P := lazymatch goal with |- ex ?P => P end in
  refine (let l := _ in ex_intro P l _).

Ltac refine_ex_and :=
  hnf;
  let P := lazymatch goal with |- ex ?P => P end in
  refine (let l := _ in ex_intro P l (conj _ _)).

Local Infix "*" := sep.
Local Infix "*" := sep : type_scope.

Ltac _syntactic_unify x y :=
  match constr:(Set) with
  | _ => is_evar x; unify x y
  | _ => is_evar y; unify x y
  | _ => lazymatch x with
         | ?f ?a => lazymatch y with ?g ?b => _syntactic_unify f g; _syntactic_unify a b end
         | (fun (a:?Ta) => ?f a)
           => lazymatch y with (fun (b:?Tb) => ?g b) =>
                               let __ := constr:(fun (a:Ta) (b:Tb) => ltac:(_syntactic_unify f g; exact Set)) in idtac end
         | let a : ?Ta := ?v in ?f a
           => lazymatch y with let b : ?Tb := ?w in ?g b =>
                               _syntactic_unify v w;
                               let __ := constr:(fun (a:Ta) (b:Tb) => ltac:(_syntactic_unify f g; exact Set)) in idtac end
         (* TODO: fail fast in more cases *)
         | _ => unify x y; constr_eq x y
         end
  end.
Tactic Notation "syntactic_unify" open_constr(x) open_constr(y) :=  _syntactic_unify x y.

Definition spec_of_swap := fun functions =>
  forall a_addr a b_addr b m R t,
    (ptsto 1 a_addr a * (ptsto 1 b_addr b * R)) m ->
    WeakestPrecondition.call (fun _ => True) (fun _ => False) (fun _ _ => True) functions
      (fst swap) t m [a_addr; b_addr]
      (fun t' m' rets => t=t'/\ (ptsto 1 a_addr b * (ptsto 1 b_addr a * R)) m' /\ rets = nil).

Lemma swap_ok : forall functions, spec_of_swap (swap::functions).
Proof.
  let body := open_constr:(_) in
  let f := open_constr:((_, (_, _, body))) in
  unify f swap; change swap with f;
    pattern body; change (bindcmd body (fun c : cmd => forall functions, spec_of_swap (("swap", (["a"; "b"], [], c)) :: functions))).
  cbv beta iota delta [bindcmd spec_of_swap].
  intros until 0. intros Hm.
  set (fun (t' : trace) (m' : mem) (rets : list word) => t = t' /\ (ptsto 1 a_addr b * (ptsto 1 b_addr a * R)%type) m' /\ rets = []) as POSTret.
  hnf.
  set (fun (t0 : trace) (m0 : mem) (l0 : locals) => WeakestPrecondition.list_map (WeakestPrecondition.get l0) [] (fun rets : list word => POSTret t0 m0 rets)) as POST.
  set (WeakestPrecondition.call (fun _ : trace => True) (fun _ : trace => False) (fun _ _ : trace => True) _) as CALL.

  refine_ex_and.
  { eabstract repeat (refine_ex_and || exact eq_refl). }
  refine_ex_and.
  { refine_ex_and.
    { repeat (refine_ex_and || exact eq_refl). }
    refine_ex_and.
    { copyprop.
      let Tm := type of m in
      let Pm := lazymatch type of Hm with ?P m => P end in
      lazymatch goal with
      | |- load ?sz ?m ?a = Some ?v
        => simple refine (load_sep sz a v _ m ((?[sep]:@Lift1Prop.impl1 Tm Pm _) m Hm));
             [ shelve | .. ]
      end.
      let __ := constr:(eq_refl : l = b) in idtac.
      copyprop.
      clear_all; eabstract (cancel; exact (RelationClasses.reflexivity _)). }
    copyprop.
    exact eq_refl. }

  copyprop.
  refine_ex_and.
  { eabstract repeat (refine_ex_and || exact eq_refl). }
  refine_ex_and.
  { refine_ex_and.
    repeat (refine_ex_and || exact eq_refl).
    copyprop.
    refine_ex_and.
    { let Tm := type of m in
      let Pm := lazymatch type of Hm with ?P m => P end in
      lazymatch goal with
      | |- load ?sz ?m ?a = Some ?v
        => simple refine (load_sep sz a v _ m ((?[sep]:@Lift1Prop.impl1 Tm Pm _) m Hm));
             [ shelve | .. ]
      end.
      let __ := constr:(eq_refl : l = a) in idtac. clear_all; eabstract (cancel; reflexivity). }
    exact eq_refl. }

  copyprop.
  let Tm := type of m in
  let Pm := lazymatch type of Hm with ?P m => P end in
  lazymatch goal with
  | |- WeakestPrecondition.store ?sz ?m ?a ?v2 ?post
    => simple refine (store_sep sz a _ v2 _ m ((_:@Lift1Prop.impl1 Tm Pm _) m Hm) post _);
         [ shelve | shelve | .. ]
  end.
  { eabstract (instantiate (2 := b); cancel; reflexivity). }
  clear Hm m; intros m Hm.
  cbv beta. (* FIXME *)

  refine_ex_and.
  { eabstract repeat (refine_ex_and || exact eq_refl). }
  refine_ex_and.
  { eabstract repeat (refine_ex_and || exact eq_refl). }
  copyprop.

  let Tm := type of m in
  let Pm := lazymatch type of Hm with ?P m => P end in
  lazymatch goal with
  | |- WeakestPrecondition.store ?sz ?m ?a ?v2 ?post
    => simple refine (store_sep sz a _ v2 _ m ((_:@Lift1Prop.impl1 Tm Pm _) m Hm) post _);
         [ shelve | shelve | .. ]
  end.
  eabstract (instantiate (2 := a); cancel; reflexivity).
  clear Hm m; intros m Hm.
  cbv beta. (* FIXME *)

  (* FIXME *)
  hnf.
  split. exact eq_refl.
  split. 2:exact eq_refl.
  assumption.
Defined.

Definition spec_of_swap_swap := fun functions =>
  forall a_addr a b_addr b m R t,
    (ptsto 1 a_addr a * (ptsto 1 b_addr b * R)) m ->
    WeakestPrecondition.call (fun _ => True) (fun _ => False) (fun _ _ => True) functions
      (fst swap_swap) t m [a_addr; b_addr]
      (fun t' m' rets => t=t' /\ (ptsto 1 a_addr a * (ptsto 1 b_addr b * R)) m' /\ rets = nil).
  
Lemma swap_swap_ok :
  forall functions, spec_of_swap functions -> spec_of_swap_swap (swap_swap::functions).
Proof.
  cbv [spec_of_swap spec_of_swap_swap].
  intros ? Hcall; intros. rename H into Hm.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  cbn [WeakestPrecondition.list_map WeakestPrecondition.expr].
  eapply WeakestPreconditionProperties.Proper_call.
  5: eapply Hcall.
  1,2,3 : cbv [Morphisms.pointwise_relation trace Basics.flip Basics.impl Morphisms.respectful]; solve [typeclasses eauto with core].
  1,2: cycle 1.
  refine ((?[sep]:@Lift1Prop.impl1 mem _ _) m Hm). reflexivity. (* TODO: ecancel *)
  intros ? m' ? (?&Hm'&?).
  clear Hm.
  clear m.
  rename m' into m.
  rename Hm' into Hm.
  subst a0.
  subst a1.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  cbn [WeakestPrecondition.list_map WeakestPrecondition.expr].
  eapply WeakestPreconditionProperties.Proper_call.
  5: eapply Hcall.
  1,2,3 : cbv [Morphisms.pointwise_relation trace Basics.flip Basics.impl Morphisms.respectful]; solve [typeclasses eauto with core].
  1,2: cycle 1.
  refine ((?[sep]:@Lift1Prop.impl1 mem _ _) m Hm). reflexivity. (* TODO: ecancel *)
  intros ? m' ? (?&Hm'&?).
  clear Hm.
  clear m.
  rename m' into m.
  rename Hm' into Hm.
  eexists.
  subst a0.
  subst a1.
  eexists.
  eexists.
  eexists.
  eexists.
  eexists.
  eassumption.
  eexists.
Qed.

Lemma link_swap_swap_swap_swap : spec_of_swap_swap (swap_swap::swap::nil).
Proof. apply swap_swap_ok, swap_ok. Qed.