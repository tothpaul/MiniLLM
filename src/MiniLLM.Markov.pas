unit MiniLLM.Markov;

interface
{$INCLUDE MINILLM.INC}
uses
  System.Math,
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  MiniLLM.Corpus;

type
  TMarkov = class
  private
    FCorpus: TCorpus;
    FScores: TList<TPair<Integer, Double>>;
    Transitions: TArray<TVector>;
    procedure Build;
  public
    constructor Create(Corpus: TCorpus);
    function NextToken(Token: Integer; Context: TVector): Integer;
    function Score(const Question: TVector; const Response: string): Double;
  end;

implementation

constructor TMarkov.Create(Corpus: TCorpus);
begin
  FCorpus := Corpus;
  SetLength(Transitions, FCorpus.Tokens.Count, FCorpus.Tokens.Count);
  FScores := TList<TPair<Integer, Double>>.Create;
  Build;
end;

procedure TMarkov.Build;
const
  Window = 3;
var
  S: string;
  i, j: Integer;
  W1, W2: Integer;
  w: Double;
begin
  {$IFDEF DEBUG_MARKOV}
    WriteLn('[DEBUG] Build Markov:');
  {$ENDIF}
  for S in FCorpus.Sentences do
  begin
    {$IFDEF DEBUG_MARKOV}
      WriteLn('  ', S);
    {$ENDIF}
    FCorpus.Tokenize(S);

    for i := 0 to FCorpus.Sentence.Count - 2 do
    begin
      W1 := FCorpus.Token(i);

      for j := i + 1 to Min(i + Window, FCorpus.Sentence.Count - 1) do
      begin
        W2 := FCorpus.Token(j);

        w :=  1/(1+j-i);

        if (W2 = FCorpus.EOS) then
          w := w * 0.2;

        w := Transitions[W1][W2] + w;
        Transitions[W1][W2] := w;
      {$IFDEF DEBUG_MARKOV}
        WriteLn('    ', FCorpus.Tokens[W1]:10, ' -> ', FCorpus.Tokens[W2]:10, ' = ', w:0:4);
      {$ENDIF}
      end;
    end;
  end;

  FCorpus.Sentence.Clear;
{$IFDEF DEBUG_MARKOV}
  WriteLn('  Final Result:');
  for i := 0 to High(Transitions) do
      for j := 0 to High(Transitions) do
       WriteLn('    ', FCorpus.Tokens[i]:10, ' -> ', FCorpus.Tokens[j]:10, ' = ', Transitions[i][j]:0:4);
{$ENDIF}

end;

function TMarkov.NextToken(Token: Integer; Context: TVector): Integer;
var
{$IFDEF DEBUG_VIEW}
  Ctx: TList<TPair<string, Double>>;
{$ENDIF}
  Candidates: TVector;
  W: Integer;
  Pair: TPair<Integer, Double>;
  RawScore, TempScore, SumScores, R: Double;
  i, K: Integer;
begin
  Result := FCorpus.EOS;

{$IFDEF DEBUG_VIEW}
  WriteLn('[DEBUG] Context: ');
  Ctx := TList<TPair<string, Double>>.Create;
  for i := 0 to High(Context) do
    Ctx.Add(TPair<string, Double>.Create(FCorpus.Tokens[i], Context[i]));
  Ctx.Sort(
    TComparer<TPair<string, Double>>.Construct(
      function(const A, B: TPair<string, Double>): Integer
      begin
        Result := Sign(B.Value - A.Value);
      end
    )
  );
  for i := 0 to Ctx.Count - 1 do
    WriteLn(' ', Ctx[i].Key:10,' -> ', Ctx[i].Value:0:4);
  Ctx.Free;

  WriteLn('[DEBUG] Current word: ', FCorpus.Tokens[Token]);

{$ENDIF}

  Candidates := Transitions[Token];
  FScores.Clear;

  try
    // 1) Calcul des scores bruts
  {$IFDEF DEBUG_VIEW}
    WriteLn('[DEBUG] Raw scores:');
  {$ENDIF}
    for W := 0 to High(Candidates) do
    begin
      RawScore := Candidates[W] ;
      if RawScore > 0.10 then
      begin
        RawScore := 0.7 * RawScore + 0.3 * FCorpus.Similarity(Context, W);
        FScores.Add(TPair<Integer, Double>.Create(W, RawScore));
      end;
    {$IFDEF DEBUG_VIEW}
      WriteLn('  ', FCorpus.Tokens[W]:10, ' -> ', Candidates[W]:0:4, ' => ', RawSCore:0:4);
    {$ENDIF}
    end;

    if FScores.Count = 0 then
      Exit;

    // 2) Tri décroissant
    FScores.Sort(
      TComparer<TPair<Integer, Double>>.Construct(
        function(const A, B: TPair<Integer, Double>): Integer
        begin
          Result := Sign(B.Value - A.Value);
        end
      )
    );

    if FScores[0].Value < 0.01 then
      Exit;

    if (FScores[0].Key = FCorpus.EOS) and (FScores[0].Value > 0.4) then
      Exit;



    // 3) Top-P (nucleus sampling)
    const P = 1.00;

   {$IFDEF DEBUG_VIEW}
     SumScores := 0;
    WriteLn('[DEBUG] After Top-P:');
    for Pair in FScores do
    begin
      WriteLn('  ', FCorpus.Tokens[Pair.Key]:10, ' -> ', Pair.Value:0:4);
      if SumScores >= 0 then
      begin
        SumScores := SumScores + Pair.Value;
        if SumScores >= P then
        begin
          WriteLn('----------Top-P----------');
          SumScores := -1;
        end;
      end;
    end;
   {$ENDIF}

    SumScores := 0;
    for i := 0 to FScores.Count - 1 do
    begin
      SumScores := SumScores + FScores[i].Value;
      if SumScores >= P then
      begin
        FScores.Count := i + 1;
        Break;
      end;
    end;

    // 4) Tirage aléatoire pondéré
    R := Random * SumScores;

  {$IFDEF DEBUG_VIEW}
    WriteLn('[DEBUG] Random draw: ', R:0:4);
  {$ENDIF}

    for Pair in FScores do
    begin
      R := R - Pair.Value;
      if (R <= 0) and (Pair.Key <> FCorpus.EOS) then
      begin
        Result := Pair.Key;
        Exit;
      end;
    end;

    // fallback
    Result := FScores[0].Key;

  finally
  {$IFDEF DEBUG_VIEW}
    WriteLn('[DEBUG] Selected: ', FCorpus.Tokens[Result]);
  {$ENDIF}
  end;
end;

function TMarkov.Score(const Question: TVector; const Response: string): Double;
var
  i, x, y, z: Integer;
  ResponseVec: TVector;
  MarkovScore : Double;
  Same: TArray<Integer>;
  SameXY: Integer;
  SameXZ: Integer;
  SameTotal: Integer;
begin
  Result := 0;
  if Response = '' then
    Exit;

  ResponseVec := FCorpus.NewVector;
  MarkovScore := 0;

  FCorpus.Tokenize(Response);

  SetLength(Same, FCorpus.Tokens.Count);

  SameXY := 0;
  SameXZ := 0;
  x := FCorpus.EOS;
  y := FCorpus.Token(0);
  for i := 1 to FCorpus.Sentence.Count - 1 do
  begin
    z := x;
    x := y;
    y := FCorpus.Token(i);
    Inc(Same[x]);
    if x = y then
      Inc(SameXY);
    if x = z then
      Inc(SameXZ);
    FCorpus.AddVector(ResponseVec, x);
    MarkovScore := MarkovScore + Transitions[x][y] - 0.5;
  end;

  SameTotal := 0;
  for i := 0 to High(Same) do
  begin
    if Same[i] > 1 then
    begin
      Inc(SameTotal, Same[i] - 1);
    end;
  end;

  Result := (0.6 * CosineSimilarity(Question, ResponseVec) + 0.4 * MarkovScore) - 0.3 * SameTotal - 0.5 * SameXY - 0.4 * SameXZ;
end;

end.
