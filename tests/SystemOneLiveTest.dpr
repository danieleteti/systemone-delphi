program SystemOneLiveTest;

{$APPTYPE CONSOLE}

// LIVE test of SystemOne.Client against a real System One server.
//   SystemOneLiveTest.exe [base-url] [model] [api-key] [chat-model]
// Defaults: Ollama on this machine, model tev1:4b, no key ('-' means no key).
// With a chat-model (any model that Ollama can chat with, e.g. minicpm-v4.6:1b)
// TSystemOneLLMAdapter is tested too, against <base-url>/v1.
// Needs Ollama >= 0.35.1 (the models need a newer one) and `ollama pull tev1:4b`.
// The checks are about the CLIENT (shape, parsing, ranges) and a few answers
// a decision model gets right at temperature 0; they are not a benchmark.

uses
  System.SysUtils, System.Diagnostics, System.Generics.Collections,
  SystemOne.Client in '..\sources\SystemOne.Client.pas';

var
  Passed, Failed: Integer;

procedure Check(const AName: string; ACondition: Boolean; const ADetail: string = '');
begin
  if ACondition then
  begin
    Inc(Passed);
    WriteLn('  [PASS] ', AName);
  end
  else
  begin
    Inc(Failed);
    WriteLn('  [FAIL] ', AName, ' -- ', ADetail);
  end;
end;

function SumOf(AAnswer: TSOAnswer): Double;
var
  P: Double;
begin
  Result := 0;
  for P in AAnswer.Probabilities.Values do
    Result := Result + P;
end;

var
  Base, Model, Key, ChatModel: string;
  Raised: Boolean;
  Client: ISystemOneClient;
  Resp: TSOResponse;
  SW: TStopwatch;
begin
  ReportMemoryLeaksOnShutdown := True;
  Base := 'http://localhost:11434';
  Model := 'tev1:4b';
  Key := '';
  if ParamCount > 0 then Base := ParamStr(1);
  if ParamCount > 1 then Model := ParamStr(2);
  if ParamCount > 2 then Key := ParamStr(3);
  if Key = '-' then Key := '';
  ChatModel := '';
  if ParamCount > 3 then ChatModel := ParamStr(4);
  WriteLn('LIVE: ', Base, '  model ', Model);
  try
    Client := TSystemOneClient.Create(Base, Key, Model);
    SW := TStopwatch.StartNew;
    Resp := Client.Ask('Hello, the August invoice is wrong: you charged me twice. ' +
      'I want a refund, it is urgent.', [
      TSO.Choice('team', 'Which team should handle this request')
        .Option('billing', 'Payments, charges, refunds')
        .Option('technical', 'Faults and service problems')
        .Option('other', 'Anything else'),
      TSO.Noul('urgent', 'The message conveys urgency'),
      TSO.Score('severity', 'How serious is the problem', ['minor', 'medium', 'serious'])]);
    SW.Stop;
    try
      WriteLn(Format('  first call %d ms (model load included), %d input tokens',
        [SW.ElapsedMilliseconds, Resp.InputTokens]));
      Check('three answers', Resp.Answers.Count = 3);
      Check('choice: billing', Resp.Answers['team'].Choice = 'billing', Resp.Answers['team'].Choice);
      Check('choice: probabilities sum to 1', Abs(SumOf(Resp.Answers['team']) - 1) < 0.01,
        FloatToStr(SumOf(Resp.Answers['team'])));
      Check('choice: confidence is high', Resp.Answers['team'].Confidence > 0.8,
        FloatToStr(Resp.Answers['team'].Confidence));
      Check('noul: urgent', Resp.Answers['urgent'].Noul > 0.7, FloatToStr(Resp.Answers['urgent'].Noul));
      Check('score: within the scale', (Resp.Answers['severity'].Score >= 0) and (Resp.Answers['severity'].Score <= 2),
        FloatToStr(Resp.Answers['severity'].Score));
      Check('score: 3 probabilities', Resp.Answers['severity'].Probabilities.Count = 3);
      WriteLn(Format('  team=%s (%.3f)  urgent=%.3f  severity=%.2f (conf %.3f)',
        [Resp.Answers['team'].Choice, Resp.Answers['team'].Confidence, Resp.Answers['urgent'].Noul,
         Resp.Answers['severity'].Score, Resp.Answers['severity'].Confidence]));
    finally
      Resp.Free;
    end;

    SW := TStopwatch.StartNew;
    Resp := Client.Ask('The router has not connected to the internet since this morning.', [
      TSO.Choice('team', 'Which team should handle this request')
        .Option('billing', 'Payments, charges, refunds')
        .Option('technical', 'Faults and service problems')
        .Option('other', 'Anything else')]);
    SW.Stop;
    try
      WriteLn(Format('  second call %d ms', [SW.ElapsedMilliseconds]));
      Check('second call: technical', Resp.Answers['team'].Choice = 'technical', Resp.Answers['team'].Choice);
      Check('second call is fast (model already loaded)', SW.ElapsedMilliseconds < 3000, IntToStr(SW.ElapsedMilliseconds));
    finally
      Resp.Free;
    end;

    // an error answer of the real server must reach the caller as ESystemOneError
    Raised := False;
    try
      Client := TSystemOneClient.Create(Base, Key, 'no-such-model:1b');
      Client.Ask('x', [TSO.Noul('a', 'b')]).Free;
    except
      on E: ESystemOneError do
        Raised := Pos('HTTP 4', E.Message) > 0;
    end;
    Check('an unknown model raises ESystemOneError with the HTTP status', Raised);

    if ChatModel <> '' then
    begin
      WriteLn('  adapter on chat model ', ChatModel);
      Client := TSystemOneLLMAdapter.Create(Base + '/v1', Key, ChatModel);
      SW := TStopwatch.StartNew;
      Resp := Client.Ask('Hello, the August invoice is wrong: you charged me twice. ' +
        'I want a refund, it is urgent.', [
        TSO.Choice('team', 'Which team should handle this request')
          .Option('billing', 'Payments, charges, refunds')
          .Option('technical', 'Faults and service problems')
          .Option('other', 'Anything else'),
        TSO.Noul('urgent', 'The message conveys urgency'),
        TSO.Score('severity', 'How serious is the problem', ['minor', 'medium', 'serious'])]);
      SW.Stop;
      try
        WriteLn(Format('  adapter call %d ms, %d input and %d output tokens',
          [SW.ElapsedMilliseconds, Resp.InputTokens, Resp.OutputTokens]));
        Check('adapter: three answers', Resp.Answers.Count = 3);
        Check('adapter: choice billing', Resp.Answers['team'].Choice = 'billing', Resp.Answers['team'].Choice);
        Check('adapter: probabilities sum to 1', Abs(SumOf(Resp.Answers['team']) - 1) < 0.01,
          FloatToStr(SumOf(Resp.Answers['team'])));
        Check('adapter: noul in range', (Resp.Answers['urgent'].Noul >= 0) and (Resp.Answers['urgent'].Noul <= 1),
          FloatToStr(Resp.Answers['urgent'].Noul));
        Check('adapter: score within the scale',
          (Resp.Answers['severity'].Score >= 0) and (Resp.Answers['severity'].Score <= 2),
          FloatToStr(Resp.Answers['severity'].Score));
        WriteLn(Format('  team=%s (%.3f)  urgent=%.3f  severity=%.2f',
          [Resp.Answers['team'].Choice, Resp.Answers['team'].Confidence, Resp.Answers['urgent'].Noul,
           Resp.Answers['severity'].Score]));
      finally
        Resp.Free;
      end;
    end;
  except
    on E: Exception do
    begin
      Inc(Failed);
      WriteLn('UNEXPECTED: ', E.ClassName, ': ', E.Message);
    end;
  end;
  WriteLn(StringOfChar('=', 50));
  WriteLn(Format('Results: %d/%d passed, %d failed', [Passed, Passed + Failed, Failed]));
  if Failed > 0 then
    ExitCode := 1;
end.
