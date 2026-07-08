unit MiniLLM.Classes;

interface
{$INCLUDE MINILLM.INC}
uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Math,
  MiniLLM.Corpus,
  MiniLLM.Markov;

type
  TMiniLLM = class
  private
    FCorpus: TCorpus;
    FMarkov: TMarkov;
    FContext: TVector;
    procedure UpdateContext(const Vector: TVector; Weight: Single); inline;
    function GenerateContext: string;
    function BestResponse(const Question: TVector): string;
  public
    constructor Create(C: TCorpus);
    function Generate(const Question: string): string;
  end;

procedure Main;

implementation

{ TMiniLLM }

constructor TMiniLLM.Create(C: TCorpus);
begin
  FCorpus := C;
  FMarkov := TMarkov.Create(FCorpus);
end;

procedure TMiniLLM.UpdateContext(const Vector: TVector; Weight: Single);
begin
  if FContext = nil then
    FContext := Vector
  else
    Combine(FContext, Vector, Weight, FContext);
end;

function TMiniLLM.GenerateContext: string;
var
  StartWord: Integer;
  Next: Integer;
  i: Integer;
begin
  Result := '';
  StartWord := FCorpus.SOS;
  for i := 1 to 10 do
  begin
    Next := FMarkov.NextToken(StartWord, FContext);
    if Next = FCorpus.EOS then Break;
    Result := Result + ' ' + FCorpus.Tokens[Next];
    UpdateContext(FCorpus.Vector(Next), 0.3);
    StartWord := Next;
  end;
end;

function TMiniLLM.BestResponse(const Question: TVector): string;
const
  MAX = 19;
var
  i: Integer;
  R: string;
  S: Double;
  T: Double;
begin
  Result := '';
  S := 0;
  for i := 0 to MAX do
  begin
    FContext := Question;
    R := GenerateContext;
    T := FMarkov.Score(Question, R);
  {$IFDEF DEBUG_REPLIES}
    WriteLn(i, ' -> "', R, '" = ', T:0:4);
  {$ENDIF}
    if T > S then
    begin
      S := T;
      Result := R;
    end;
  end;
end;

function TMiniLLM.Generate(const Question: string): string;
begin
  Result := BestResponse(FCorpus.SentenceVector(Question));

  if Result = '' then
  {$IFDEF FRENCH}
    Result := 'Je ne comprends pas la question.';
  {$ELSE}
    Result := 'I don''t understand the question.';
  {$ENDIF}
end;

procedure Main;
var
  Corpus: TCorpus;
  LLM: TMiniLLM;
  Input: string;

begin
{$IFDEF RANDOMIZE}Randomize;{$ENDIF}
  Corpus := TCorpus.Create;

  LLM := TMiniLLM.Create(Corpus);

  WriteLn('Mini-LLM Delphi (Console)');
{$IFDEF FRENCH}
  WriteLn('Corpus chargé. Pose une question :');
{$ELSE}
  WriteLn('Corpus loaded. Ask a question :');
{$ENDIF}
  WriteLn;

  while True do
  begin
    Write('> ');
    ReadLn(Input);

    if Input = 'quit' then Break;

  {$IFDEF FRENCH}
    WriteLn('Réponse : ', LLM.Generate(Input));
  {$ELSE}
    WriteLn('Answer : ', LLM.Generate(Input));
  {$ENDIF}
    WriteLn;
  end;
end;

end.
