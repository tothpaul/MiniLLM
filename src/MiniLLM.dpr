program MiniLLM;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  MiniLLM.Classes in 'MiniLLM.Classes.pas',
  MiniLLM.Markov in 'MiniLLM.Markov.pas',
  MiniLLM.Corpus in 'MiniLLM.Corpus.pas';

begin
  try
    { TODO -oUser -cConsole Main : Insérer du code ici }
    Main;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
