unit MiniLLM.Corpus;

interface
{$INCLUDE MINILLM.INC}
uses
  System.Math,
  System.Classes,
  System.SysUtils,
  System.Generics.Collections;

const
  StartOfSentence = '<SOS>';
  EndOfSentence = '<EOS>';

type
  TVector = array of Double;

  TTokenProc = function(const S: string): Integer of object;

  TCorpus = class
  private
    procedure ForeachToken(const S: string; Proc: TTokenProc);
    function AddToken(const S: string): Integer;
  public
    Sentences: TArray<string>;
    Sentence: TStringList;
    Tokens: TStringList;
    SOS, EOS: Integer;
    PMI: TArray<TVector>; // Pointwise Mutual Information
    constructor Create;
    procedure Load;
    procedure BuildVocabulary;
    procedure BuildEmbeddings;
    function Distance(i, j: Integer): Double;
    function NewVector: TVector;
    procedure Tokenize(const S: string);
    function Token(Index: Integer): Integer;
    function Vector(Token: Integer): TVector;
    procedure AddVector(var Vector: TVector; Token: Integer);
    function SentenceVector(const S: string): TVector;
    function Similarity(const V: TVector; Token: Integer): Double;
  end;

function CosineSimilarity(const A, B: TVector): Double;
procedure Combine(const A, B: TVector; Factor: Single; var Result: TVector);

implementation

function CosineSimilarity(const A, B: TVector): Double;
var
  Dot, NA, NB: Double;
  i: Integer;
begin
  Dot := 0; NA := 0; NB := 0;

  for i := 0 to High(A) do
  begin
    Dot := Dot + A[i] * B[i];
    NA := NA + A[i] * A[i];
    NB := NB + B[i] * B[i];
  end;

  if (NA = 0) or (NB = 0) then
    Exit(0);

  Result := Dot / (Sqrt(NA) * Sqrt(NB));
end;

procedure Combine(const A, B: TVector; Factor: Single; var Result: TVector);
var
  k: Double;
  i: Integer;
  c: Double;
  n: Double;
begin
  n := 0;
  k := 1 - Factor;
  for i := 0 to High(Result) do
  begin
    c := k * A[i] + Factor * B[i];
    Result[i] := c;
    n := n + c * c;
  end;
  n := 1 / Sqrt(n);
  for i := 0 to High(Result) do
  begin
    Result[i] := Result[i] * n;
  end;
end;

{ TCorpus }

constructor TCorpus.Create;
begin
  Tokens := TStringList.Create(TDuplicates.dupIgnore, True, False);
  Sentence := TStringList.Create;
  Load;
  BuildVocabulary;
  BuildEmbeddings;
end;

procedure TCorpus.Load;
begin
  // Micro-corpus pédagogique
{$IFDEF FRENCH}
  Sentences := [
    'le chat mange la souris',
    'c''est bon un bon fromage',
    'le chat dort sur une chaise',
    'le chat est gourmant',
    'la souris mange du fromage',
    'la chaise est rouge',
    'la pomme est belle'
  ];
{$ELSE}
  Sentences := [
    'the cat eats the mouse',
    'the mouse eats cheese',
    'cheese is good',
    'the cat sleeps on a chair',
    'the chair is red',
    'the apple is beautiful',
    'the mouse is clever',
    'the cat is a glutton'
  ];
{$ENDIF}
end;

procedure TCorpus.BuildVocabulary;
var
  S: string;
begin
  Tokens.Clear;
  Tokens.Add(StartOfSentence);
  Tokens.Add(EndOfSentence);
  for S in Sentences do
  begin
    ForEachToken(S, Tokens.Add);
  end;
  SOS := Tokens.IndexOf(StartOfSentence);
  EOS := Tokens.IndexOf(EndOfSentence);
end;

function TCorpus.NewVector: TVector;
begin
  SetLength(Result, Tokens.Count);
end;

procedure TCorpus.Tokenize(const S: string);
begin
  Sentence.Clear;
  Sentence.AddObject(StartOfSentence, TObject(SOS));
  ForeachToken(S, AddToken);
  Sentence.AddObject(EndOfSentence, TObject(EOS));
end;

function TCorpus.Token(Index: Integer): Integer;
begin
  Result := Integer(Sentence.Objects[Index]);
end;

function TCorpus.AddToken(const S: string): Integer;
begin
  Result := Tokens.IndexOf(S);
  if Result >= 0 then
    Sentence.AddObject(S, TObject(Result));
{$IFDEF DEBUG_VIEW}
  Write(S: 10, ' -> ');
  if Result >= 0 then
    WriteLn(Result)
  else
    WriteLn('ignored');
{$ENDIF}
end;

procedure TCorpus.ForeachToken(const S: string; Proc: TTokenProc);
var
  start: Integer;
  index: Integer;
begin
  start := 1;
  index := 1;
  while index <= Length(S) do
  begin
    case S[Index] of
       #0..'&', // keep Quote
      '('..'@':
      begin
        if index > start then
        begin
          Proc(Copy(S, start, index - start));
        end;
        start := index + 1;
      end;
    end;
    Inc(Index);
  end;
  if index > start then
  begin
    Proc(Copy(S, start));
  end;
end;

procedure TCorpus.BuildEmbeddings;
const
  Window = 3;
var
  S: string;
  i, j: Integer;
  x, y: Integer;
  w: Double;
  Total: Double;
  SubTotal: Double;
  Freq: TArray<Double>;
  Pxy, Px, Py: Double;
begin
  // Initialisation des vecteurs
  SetLength(PMI, Tokens.Count, Tokens.Count);

  Total := 0;
  SetLength(Freq, Tokens.Count);

  for S in Sentences do
  begin
    Tokenize(S);

    for i := 0 to Sentence.Count - 1 do
    begin
      x := Token(i);
      SubTotal := 0;
      for j := Max(0, i - Window) to Min(Sentence.Count - 1, i + Window) do
      begin
        if i = j then Continue;
        // Co-occurrence
        y := Token(j);
        w := Distance(i, j);
        if y = EOS then
          w := w * 0.1;
        PMI[x][y] := PMI[x][y] + w;
        SubTotal := SubTotal + w;
      end;
      Freq[x] := Freq[x] + SubTotal;
      Total := Total + SubTotal;
    end;
  end;

  for x := 0 to Tokens.Count - 1 do
  begin
    for y := 0 to Tokens.Count - 1 do
    begin
      Pxy := PMI[x, y] / Total;
      Px := Freq[x] / Total;
      Py := Freq[y] / Total;
      if (Pxy > 0.001) and (Px > 0.001) and (Py > 0.001) then
        PMI[x][y] := Ln(Pxy / (Px * Py))
      else
        PMI[x][y] := 0;
    end;
  end;
  Sentence.Clear;
end;

function TCorpus.Distance(i, j: Integer): Double;
begin
  Result := 1/(1 + Abs(i - j));
//  Result := Exp(-1.0 * Abs(i - j));
end;

function TCorpus.Vector(Token: Integer): TVector;
begin
  Result := PMI[Token];
end;

procedure TCorpus.AddVector(var Vector: TVector; Token: Integer);
var
  i: Integer;
begin
  for i := 0 to High(Vector) do
    Vector[i] := Vector[i] + PMI[Token][i];
end;

function TCorpus.SentenceVector(const S: string): TVector;
var
  i: Integer;
begin
  Tokenize(S);
  Result := NewVector;
  for i := 0 to Sentence.Count - 1 do
  begin
    AddVector(Result, Token(i));
  end;
  Sentence.Clear;
end;

function TCorpus.Similarity(const V: TVector; Token: Integer): Double;
begin
  Result := CosineSimilarity(V, PMI[Token])
end;

end.
