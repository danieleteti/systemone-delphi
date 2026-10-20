program Triage;

{$APPTYPE CONSOLE}

// Quickstart sample: ask three typed questions about a support message.
//
//   Triage.exe ["the message to classify"]
//
// Needs Ollama (>= 0.35.1) with a System One model:  ollama pull tev1:4b
// For Jev instead, replace the client with
//   TSystemOneClient.Create('https://api.typesafe.ai', GetEnvironmentVariable('TYPESAFE_API_KEY'), 'jev-latest')

uses
  System.SysUtils,
  SystemOne.Client in '..\sources\SystemOne.Client.pas';

var
  Client: ISystemOneClient;
  Response: TSOResponse;
  Message: string;
begin
  Message := 'Hello, the August invoice is wrong: you charged me twice. I want a refund, it is urgent.';
  if ParamCount > 0 then
    Message := ParamStr(1);
  try
    Client := TSystemOneClient.Create('http://localhost:11434', '', 'tev1:4b');
    Response := Client.Ask(Message, [
      TSO.Choice('team', 'Which team should handle this request')
        .Option('billing', 'Payments, charges, refunds')
        .Option('technical', 'Faults and service problems')
        .Option('other', 'Anything else'),
      TSO.Score('severity', 'How serious is the problem', ['minor', 'medium', 'serious']),
      TSO.Noul('urgent', 'The message conveys urgency')]);
    try
      WriteLn(Format('team     : %s  (confidence %.2f)',
        [Response.Answers['team'].Choice, Response.Answers['team'].Confidence]));
      WriteLn(Format('severity : %.2f of 0..2', [Response.Answers['severity'].Score]));
      WriteLn(Format('urgent   : %.2f', [Response.Answers['urgent'].Noul]));
      WriteLn(Format('model %s, %d input tokens', [Response.Model, Response.InputTokens]));
    finally
      Response.Free;
    end;
  except
    on E: Exception do
    begin
      WriteLn(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
