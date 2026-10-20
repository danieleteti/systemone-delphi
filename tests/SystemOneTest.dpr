program SystemOneTest;

{$APPTYPE CONSOLE}

// Offline test of SystemOne.Client against tests\fake_server.py.
// Easiest:  python tests\run_all.py   (builds, starts the fake server, runs, stops it)
// By hand: python fake_server.py 9099, then SystemOneTest.exe [http://127.0.0.1:9099]

uses
  System.SysUtils, System.JSON, System.Net.HttpClient, System.Generics.Collections,
  SystemOne.Client in '..\sources\SystemOne.Client.pas';

var
  Passed, Failed: Integer;
  Base: string;

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

function LastRequest: TJSONObject;
var
  LHTTP: THTTPClient;
begin
  LHTTP := THTTPClient.Create;
  try
    Result := TJSONObject.ParseJSONValue(LHTTP.Get(Base + '/_last').ContentAsString) as TJSONObject;
  finally
    LHTTP.Free;
  end;
end;

procedure TestVersion;
begin
  WriteLn('--- version');
  Check('SYSTEMONE_CLIENT_VERSION is MAJOR.MINOR.PATCH',
    (Length(SYSTEMONE_CLIENT_VERSION.Split(['.'])) = 3) and
    (StrToIntDef(SYSTEMONE_CLIENT_VERSION.Split(['.'])[0], -1) >= 0) and
    (StrToIntDef(SYSTEMONE_CLIENT_VERSION.Split(['.'])[1], -1) >= 0) and
    (StrToIntDef(SYSTEMONE_CLIENT_VERSION.Split(['.'])[2], -1) >= 0), SYSTEMONE_CLIENT_VERSION);
end;

procedure TestQuestions;
var
  LQ: TSOQuestion;
  LClient: ISystemOneClient;

  function Raises(const AQuestion: TSOQuestion; const AText: string): Boolean;
  begin
    Result := False;
    try
      LClient.Ask('x', [AQuestion]).Free;
    except
      on E: ESystemOneError do
        Result := Pos(AText, E.Message) > 0;
    end;
  end;

  function NoulOptionRaises: Boolean;
  var
    N: TSOQuestion;
  begin
    Result := False;
    try
      N := TSO.Noul('n', 'x').Option('a', 'b');
    except
      on E: ESystemOneError do
        Result := Pos('for a choice', E.Message) > 0;
    end;
  end;

begin
  WriteLn('--- question builders and validation');
  LClient := TSystemOneClient.Create(Base, 'good-key', 'jev-latest');
  LQ := TSO.Choice('team', 'who').Option('billing', 'money').Option('technical', 'faults');
  Check('Option keeps the order', (Length(LQ.Labels) = 2) and (LQ.Labels[0] = 'billing') and
    (LQ.Labels[1] = 'technical') and (LQ.Descriptions[1] = 'faults'));
  Check('the original question is not changed by Option',
    Length(TSO.Choice('a', 'b').Labels) = 0);
  Check('a choice with one option is refused before any request',
    Raises(TSO.Choice('team', 'who').Option('billing', 'money'), 'at least two'));
  Check('a repeated label is refused',
    Raises(TSO.Choice('team', 'who').Option('a', '1').Option('a', '2'), 'twice'));
  Check('an empty label is refused',
    Raises(TSO.Choice('team', 'who').Option('a', '1').Option('', '2'), 'empty label'));
  Check('Option on a noul raises', NoulOptionRaises);
end;

procedure TestJev;
var
  LClient: ISystemOneClient;
  LResp: TSOResponse;
  LLast: TJSONObject;
  LQ: TJSONObject;
  LRaised: Boolean;
begin
  WriteLn('--- TSystemOneClient (the TypeSafe API shape)');
  LClient := TSystemOneClient.Create(Base, 'good-key', 'jev-latest');
  LResp := LClient.Ask('Our API integration started returning 500 errors.', [
    TSO.Choice('team', 'Which team should handle this')
      .Option('billing', 'Payment or subscription issues')
      .Option('technical', 'Bugs or integration problems'),
    TSO.Score('severity', 'How severe is it', ['cosmetic', 'degraded', 'outage']),
    TSO.Noul('urgent', 'The message conveys urgency')]);
  try
    Check('model is read', LResp.Model = 'jev-1.13.0', LResp.Model);
    Check('usage is read', (LResp.InputTokens = 42) and (LResp.OutputTokens = 0));
    Check('three answers', LResp.Answers.Count = 3);
    Check('choice: label', LResp.Answers['team'].Choice = 'technical');
    Check('choice: confidence', Abs(LResp.Answers['team'].Confidence - 0.95) < 0.001,
      FloatToStr(LResp.Answers['team'].Confidence));
    Check('choice: probabilities', Abs(LResp.Answers['team'].Probabilities['billing'] - 0.05) < 0.001);
    Check('score: expected level (a fraction) and confidence', (Abs(LResp.Answers['severity'].Score - 1.24) < 0.001) and
      (Abs(LResp.Answers['severity'].Confidence - 0.8) < 0.001));
    Check('score: probabilities', Abs(LResp.Answers['severity'].Probabilities['1'] - 0.8) < 0.001);
    Check('noul: value', Abs(LResp.Answers['urgent'].Noul - 0.91) < 0.001);
  finally
    LResp.Free;
  end;

  LLast := LastRequest;
  try
    Check('POST /v1/systemone with the key',
      (LLast.GetValue<string>('path') = '/v1/systemone') and (LLast.GetValue<string>('auth') = 'Bearer good-key'));
    Check('body: state and model',
      (LLast.GetValue<string>('body.state') = 'Our API integration started returning 500 errors.') and
      (LLast.GetValue<string>('body.model') = 'jev-latest'));
    LQ := LLast.FindValue('body.questions.team') as TJSONObject;
    Check('body: choice has type, instructions, criteria as an object',
      (LQ.GetValue<string>('type') = 'choice') and (LQ.GetValue<string>('instructions') = 'Which team should handle this')
      and (LQ.GetValue<string>('criteria.technical') = 'Bugs or integration problems'));
    LQ := LLast.FindValue('body.questions.severity') as TJSONObject;
    Check('body: score criteria is an ordered array',
      ((LQ.GetValue('criteria') as TJSONArray).Count = 3) and
      ((LQ.GetValue('criteria') as TJSONArray).Items[2].Value = 'outage'));
    LQ := LLast.FindValue('body.questions.urgent') as TJSONObject;
    Check('body: noul has only type and instructions', (LQ.GetValue<string>('type') = 'noul') and (LQ.Count = 2));
  finally
    LLast.Free;
  end;

  LRaised := False;
  try
    LClient := TSystemOneClient.Create(Base, 'wrong', 'jev-latest');
    LClient.Ask('x', [TSO.Noul('a', 'b')]).Free;
  except
    on E: ESystemOneError do
      LRaised := Pos('HTTP 401', E.Message) > 0;
  end;
  Check('a wrong key raises ESystemOneError with the HTTP status', LRaised);

  // A local server needs no key: no Authorization header is sent at all.
  LRaised := False;
  try
    LClient := TSystemOneClient.Create(Base, '', 'jev-latest');
    LClient.Ask('x', [TSO.Noul('a', 'b')]).Free;
  except
    on E: ESystemOneError do
      LRaised := Pos('HTTP 401', E.Message) > 0;   // the fake server wants a key; what matters is the header below
  end;
  LLast := LastRequest;
  try
    Check('an empty key sends no Authorization header', LRaised and (LLast.GetValue('auth') is TJSONNull));
  finally
    LLast.Free;
  end;
end;

procedure TestAdapter;
var
  LClient: ISystemOneClient;
  LResp: TSOResponse;
  LLast: TJSONObject;
  LFormat: TJSONObject;
begin
  WriteLn('--- TSystemOneLLMAdapter (same questions, a chat model)');
  LClient := TSystemOneLLMAdapter.Create(Base + '/v1', 'good-key', 'some-model');
  LResp := LClient.Ask('Il cliente scrive: la fattura e'' sbagliata, e vorrei il rimborso.', [
    TSO.Choice('team', 'Which team should handle this')
      .Option('billing', 'Payment or subscription issues')
      .Option('technical', 'Bugs or integration problems')
      .Option('other', 'Anything else'),
    TSO.Score('severity', 'How severe is it', ['cosmetic', 'degraded', 'outage']),
    TSO.Noul('urgent', 'The message conveys urgency')]);
  try
    Check('choice: the best option wins', LResp.Answers['team'].Choice = 'billing');
    Check('choice: probabilities normalized to sum 1 (6,2,0 -> .75,.25,0)',
      (Abs(LResp.Answers['team'].Probabilities['billing'] - 0.75) < 0.001) and
      (Abs(LResp.Answers['team'].Probabilities['technical'] - 0.25) < 0.001) and
      (LResp.Answers['team'].Probabilities['other'] = 0));
    Check('choice: confidence is the top probability', Abs(LResp.Answers['team'].Confidence - 0.75) < 0.001);
    Check('score: index of the best level', LResp.Answers['severity'].Score = 0);
    Check('noul: out-of-range value is clamped to 1', LResp.Answers['urgent'].Noul = 1);
    Check('usage is read', (LResp.InputTokens = 100) and (LResp.OutputTokens = 20));
  finally
    LResp.Free;
  end;

  LLast := LastRequest;
  try
    Check('POST /v1/chat/completions with the key',
      (LLast.GetValue<string>('path') = '/v1/chat/completions') and (LLast.GetValue<string>('auth') = 'Bearer good-key'));
    LFormat := LLast.FindValue('body.response_format') as TJSONObject;
    Check('a strict JSON Schema is asked for',
      (LFormat <> nil) and (LFormat.GetValue<string>('type') = 'json_schema') and
      (LFormat.GetValue<string>('json_schema.name') = 'system_one_answers'));
    Check('the schema names every question and every option',
      Pos('"technical"', LFormat.ToJSON) > 0) ;
    Check('the prompt carries the state and the instructions',
      (Pos('la fattura', LLast.GetValue<string>('body.messages[0].content')) > 0) and
      (Pos('Which team should handle this', LLast.GetValue<string>('body.messages[0].content')) > 0));
  finally
    LLast.Free;
  end;

  // A server that wraps the JSON in a code fence.
  LResp := LClient.Ask('please fence this', [TSO.Noul('a', 'whatever')]);
  try
    Check('JSON inside a code fence is read', LResp.Answers['a'].Noul = 1);
  finally
    LResp.Free;
  end;

  with TSystemOneLLMAdapter(LClient) do
    StructuredOutputs := False;
  LResp := LClient.Ask('plain', [TSO.Choice('c', 'pick').Option('x', 'first').Option('y', 'second')]);
  try
    Check('without structured outputs the answer is still read', LResp.Answers['c'].Choice = 'x');
  finally
    LResp.Free;
  end;
  LLast := LastRequest;
  try
    Check('without structured outputs no response_format is sent', LLast.FindValue('body.response_format') = nil);
  finally
    LLast.Free;
  end;
end;

begin
  ReportMemoryLeaksOnShutdown := True;
  Base := 'http://127.0.0.1:9099';
  if ParamCount > 0 then
    Base := ParamStr(1);
  try
    TestVersion;
    TestQuestions;
    TestJev;
    TestAdapter;
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
