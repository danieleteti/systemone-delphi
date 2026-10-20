// ***************************************************************************
//
// System One client for Delphi
//
// A System One model (TypeSafe "Jev" is the first) is not a chat model: it
// takes a STATE (text or JSON) and a set of typed QUESTIONS, and answers with
// typed values and a probability distribution, in tens or hundreds of
// milliseconds and with no text to parse. It decides; it does not write.
//
// This unit has one interface, ISystemOneClient, and two implementations:
//
//   TSystemOneClient            the real TypeSafe API (POST /v1/systemone).
//   TSystemOneLLMAdapter  the same questions answered by any OpenAI-compatible
//                         chat model (OpenAI, OpenRouter, Ollama, vLLM...),
//                         in the way of the open-source system-one-adapter
//                         (MIT). Slower and dearer than Jev, and the
//                         probabilities are the model's own opinion, not
//                         calibrated. It exists to build and test the flow
//                         without access to Jev and to compare the two.
//
// https://github.com/danieleteti/systemone-delphi  -  Apache-2.0
//
// Question types (the ones Jev's API documents):
//   Choice  pick one label among several; answer = choice + probabilities
//           + confidence
//   Score   a level on an ordered scale; answer = score + probabilities
//           + confidence + legend
//   Noul    a yes/no as a number in [0,1]
// "Box" (a region of an image) is not supported here.
//
// ***************************************************************************

unit SystemOne.Client;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.JSON;

const
  // Semantic Versioning (https://semver.org). Keep in step with README.md and
  // CHANGELOG.md, and tag the release as v<this>.
  SYSTEMONE_CLIENT_VERSION = '0.9.0';

type
  ESystemOneError = class(Exception);

  TSOKind = (Choice, Score, Noul);

  TSOQuestion = record
    ID: string;
    Kind: TSOKind;
    Instructions: string;
    // Choice: label -> description. Score: level 0..N-1, in order, label = index.
    Labels: TArray<string>;
    Descriptions: TArray<string>;
    // Choice: adds an option; the options keep the order in which you add them.
    function Option(const ALabel, ADescription: string): TSOQuestion;
  end;

  TSOAnswer = class
  public
    Kind: TSOKind;
    Choice: string;          // Choice
    Score: Double;           // Score: Jev/Ollama return the expected level (1.24 = between 1 and 2), not only an integer
    Noul: Double;            // Noul, 0..1
    Confidence: Double;      // Choice and Score, 0..1
    Probabilities: TDictionary<string, Double>; // Choice and Score
    constructor Create;
    destructor Destroy; override;
  end;

  TSOResponse = class
  public
    Model: string;
    InputTokens, OutputTokens: Integer;
    Answers: TObjectDictionary<string, TSOAnswer>;
    constructor Create;
    destructor Destroy; override;
  end;

  // Builders for the questions.
  TSO = record
    // Then add the options: TSO.Choice('team', '...').Option('billing', '...').Option('other', '...')
    class function Choice(const AID, AInstructions: string): TSOQuestion; static;
    // ALevels: description of level 0, of level 1, ... (the score is the index)
    class function Score(const AID, AInstructions: string;
      const ALevels: array of string): TSOQuestion; static;
    class function Noul(const AID, AInstructions: string): TSOQuestion; static;
  end;

  ISystemOneClient = interface
    ['{6E0D5C0A-3B0F-4C2E-9B52-2D3F7C1A9E11}']
    // The caller owns the response. AState is text, or the text of a JSON.
    function Ask(const AState: string; const AQuestions: array of TSOQuestion): TSOResponse;
  end;

  // The real thing (Jev: key from the TypeSafe console, early access) and any
  // server with the same API: Ollama >= 0.35.1 (http://localhost:11434, models
  // tev1, nimble, clef...; tried with tev1:4b) and Ollaya (same API, not tried).
  // For a local server pass '' as the key.
  TSystemOneClient = class(TInterfacedObject, ISystemOneClient)
  private
    FAPIKey, FModel, FBaseURL: string;
    FTimeoutMs: Integer;
  public
    // No default server: you say where the model is. Jev: 'https://api.typesafe.ai',
    // your key, 'jev-latest'. Ollama: 'http://localhost:11434', '', 'tev1:4b'.
    constructor Create(const ABaseURL, AAPIKey, AModel: string);
    function Ask(const AState: string; const AQuestions: array of TSOQuestion): TSOResponse;
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;
  end;

  // The same interface answered by a chat model. ABaseURL is the root of an
  // OpenAI-compatible API, with /v1: https://api.openai.com/v1,
  // https://openrouter.ai/api/v1, http://localhost:11434/v1 (Ollama).
  TSystemOneLLMAdapter = class(TInterfacedObject, ISystemOneClient)
  private
    FAPIKey, FModel, FBaseURL: string;
    FTimeoutMs: Integer;
    FStructuredOutputs: Boolean;
    function BuildSchema(const AQuestions: array of TSOQuestion): TJSONObject;
    function BuildPrompt(const AState: string; const AQuestions: array of TSOQuestion): string;
  public
    constructor Create(const ABaseURL, AAPIKey, AModel: string);
    function Ask(const AState: string; const AQuestions: array of TSOQuestion): TSOResponse;
    // True: ask the provider for a JSON Schema (response_format). Turn it off for
    // a server that rejects the field; the answer is then read from the text.
    property StructuredOutputs: Boolean read FStructuredOutputs write FStructuredOutputs;
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;
  end;

implementation

uses
  System.Net.HttpClient, System.Net.URLClient, System.Math, System.StrUtils;

function PostJSON(const AURL, AAPIKey: string; ABody: TJSONObject; ATimeoutMs: Integer): TJSONObject;
var
  LHTTP: THTTPClient;
  LStream: TStringStream;
  LResp: IHTTPResponse;
  LValue: TJSONValue;
  LHeaders: TNetHeaders;
begin
  LHTTP := THTTPClient.Create;
  try
    LHTTP.ConnectionTimeout := 10000;
    LHTTP.ResponseTimeout := ATimeoutMs;
    LStream := TStringStream.Create(ABody.ToJSON, TEncoding.UTF8);
    try
      LHeaders := [TNameValuePair.Create('Content-Type', 'application/json')];
      if AAPIKey <> '' then
        LHeaders := LHeaders + [TNameValuePair.Create('Authorization', 'Bearer ' + AAPIKey)];
      LResp := LHTTP.Post(AURL, LStream, nil, LHeaders);
    finally
      LStream.Free;
    end;
    if (LResp.StatusCode < 200) or (LResp.StatusCode >= 300) then
      raise ESystemOneError.CreateFmt('HTTP %d from %s: %s',
        [LResp.StatusCode, AURL, Copy(LResp.ContentAsString(TEncoding.UTF8), 1, 400)]);
    LValue := TJSONObject.ParseJSONValue(LResp.ContentAsString(TEncoding.UTF8));
    if not (LValue is TJSONObject) then
    begin
      LValue.Free;
      raise ESystemOneError.Create('The answer is not a JSON object');
    end;
    Result := TJSONObject(LValue);
  finally
    LHTTP.Free;
  end;
end;

function KindName(AKind: TSOKind): string;
begin
  case AKind of
    TSOKind.Choice: Result := 'choice';
    TSOKind.Score: Result := 'score';
  else
    Result := 'noul';
  end;
end;

{ TSOAnswer }

constructor TSOAnswer.Create;
begin
  inherited;
  Probabilities := TDictionary<string, Double>.Create;
end;

destructor TSOAnswer.Destroy;
begin
  Probabilities.Free;
  inherited;
end;

{ TSOResponse }

constructor TSOResponse.Create;
begin
  inherited;
  Answers := TObjectDictionary<string, TSOAnswer>.Create([doOwnsValues]);
end;

destructor TSOResponse.Destroy;
begin
  Answers.Free;
  inherited;
end;

{ TSOQuestion }

function TSOQuestion.Option(const ALabel, ADescription: string): TSOQuestion;
begin
  if Kind <> TSOKind.Choice then
    raise ESystemOneError.CreateFmt('Question "%s": Option is for a choice, not for a %s',
      [ID, KindName(Kind)]);
  Result := Self;
  SetLength(Result.Labels, Length(Labels) + 1);
  SetLength(Result.Descriptions, Length(Descriptions) + 1);
  Result.Labels[High(Result.Labels)] := ALabel;
  Result.Descriptions[High(Result.Descriptions)] := ADescription;
end;

{ TSO }

class function TSO.Choice(const AID, AInstructions: string): TSOQuestion;
begin
  Result := Default(TSOQuestion);
  Result.ID := AID;
  Result.Kind := TSOKind.Choice;
  Result.Instructions := AInstructions;
end;

class function TSO.Score(const AID, AInstructions: string;
  const ALevels: array of string): TSOQuestion;
var
  I: Integer;
begin
  if Length(ALevels) < 2 then
    raise ESystemOneError.CreateFmt('Question "%s": a score needs at least two levels', [AID]);
  Result := Default(TSOQuestion);
  Result.ID := AID;
  Result.Kind := TSOKind.Score;
  Result.Instructions := AInstructions;
  SetLength(Result.Labels, Length(ALevels));
  SetLength(Result.Descriptions, Length(ALevels));
  for I := 0 to High(ALevels) do
  begin
    Result.Labels[I] := I.ToString;
    Result.Descriptions[I] := ALevels[I];
  end;
end;

class function TSO.Noul(const AID, AInstructions: string): TSOQuestion;
begin
  Result := Default(TSOQuestion);
  Result.ID := AID;
  Result.Kind := TSOKind.Noul;
  Result.Instructions := AInstructions;
end;

// What the builders cannot check, because a choice is completed after TSO.Choice.
procedure ValidateQuestions(const AQuestions: array of TSOQuestion);
var
  LQ: TSOQuestion;
  I, J: Integer;
begin
  for LQ in AQuestions do
  begin
    if LQ.ID = '' then
      raise ESystemOneError.Create('A question has no id');
    if LQ.Kind <> TSOKind.Noul then
      if Length(LQ.Labels) < 2 then
        raise ESystemOneError.CreateFmt('Question "%s": a %s needs at least two options',
          [LQ.ID, KindName(LQ.Kind)]);
    for I := 0 to High(LQ.Labels) do
    begin
      if LQ.Labels[I] = '' then
        raise ESystemOneError.CreateFmt('Question "%s": an option has an empty label', [LQ.ID]);
      for J := 0 to I - 1 do
        if LQ.Labels[J] = LQ.Labels[I] then
          raise ESystemOneError.CreateFmt('Question "%s": the option "%s" is there twice', [LQ.ID, LQ.Labels[I]]);
    end;
  end;
end;

{ Question -> the JSON of the Jev API }
function QuestionToJSON(const AQuestion: TSOQuestion): TJSONObject;
var
  LCriteria: TJSONObject;
  LLevels: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', KindName(AQuestion.Kind));
  Result.AddPair('instructions', AQuestion.Instructions);
  case AQuestion.Kind of
    TSOKind.Choice:
      begin
        LCriteria := TJSONObject.Create;
        for I := 0 to High(AQuestion.Labels) do
          LCriteria.AddPair(AQuestion.Labels[I], AQuestion.Descriptions[I]);
        Result.AddPair('criteria', LCriteria);
      end;
    TSOKind.Score:
      begin
        LLevels := TJSONArray.Create;
        for I := 0 to High(AQuestion.Descriptions) do
          LLevels.Add(AQuestion.Descriptions[I]);
        Result.AddPair('criteria', LLevels);
      end;
  end;
end;

// Fills the probabilities of an answer from a JSON object (label -> p).
procedure ReadProbabilities(AAnswer: TSOAnswer; AProbs: TJSONObject);
var
  LPair: TJSONPair;
begin
  if AProbs = nil then
    Exit;
  for LPair in AProbs do
    AAnswer.Probabilities.AddOrSetValue(LPair.JsonString.Value,
      (LPair.JsonValue as TJSONNumber).AsDouble);
end;

{ TSystemOneClient }

constructor TSystemOneClient.Create(const ABaseURL, AAPIKey, AModel: string);
begin
  inherited Create;
  // Jev needs a key (TYPESAFE_API_KEY); a local server (Ollama, Ollaya) needs none.
  FAPIKey := AAPIKey;
  FModel := AModel;
  FBaseURL := ABaseURL.TrimRight(['/']);
  FTimeoutMs := 30000;
end;

function TSystemOneClient.Ask(const AState: string; const AQuestions: array of TSOQuestion): TSOResponse;
var
  LBody, LQuestions, LResp, LAnswers, LAns, LUsage: TJSONObject;
  LQ: TSOQuestion;
  LPair: TJSONPair;
  LAnswer: TSOAnswer;
  LType: string;
  LValue: TJSONValue;
begin
  if Length(AQuestions) = 0 then
    raise ESystemOneError.Create('No question');
  ValidateQuestions(AQuestions);
  LBody := TJSONObject.Create;
  try
    LBody.AddPair('state', AState);
    LBody.AddPair('model', FModel);
    LQuestions := TJSONObject.Create;
    LBody.AddPair('questions', LQuestions);
    for LQ in AQuestions do
      LQuestions.AddPair(LQ.ID, QuestionToJSON(LQ));
    LResp := PostJSON(FBaseURL + '/v1/systemone', FAPIKey, LBody, FTimeoutMs);
  finally
    LBody.Free;
  end;
  try
    Result := TSOResponse.Create;
    try
      Result.Model := LResp.GetValue<string>('model', '');
      LUsage := LResp.GetValue('usage') as TJSONObject;
      if LUsage <> nil then
      begin
        Result.InputTokens := LUsage.GetValue<Integer>('input_tokens', 0);
        Result.OutputTokens := LUsage.GetValue<Integer>('output_tokens', 0);
      end;
      LAnswers := LResp.GetValue('answers') as TJSONObject;
      if LAnswers = nil then
        raise ESystemOneError.Create('The answer has no "answers"');
      for LPair in LAnswers do
      begin
        LAns := LPair.JsonValue as TJSONObject;
        LType := LAns.GetValue<string>('type', '');
        LAnswer := TSOAnswer.Create;
        Result.Answers.Add(LPair.JsonString.Value, LAnswer);
        if SameText(LType, 'choice') then
        begin
          LAnswer.Kind := TSOKind.Choice;
          LAnswer.Choice := LAns.GetValue<string>('choice', '');
          LAnswer.Confidence := LAns.GetValue<Double>('confidence', 0);
          ReadProbabilities(LAnswer, LAns.GetValue('probabilities') as TJSONObject);
        end
        else if SameText(LType, 'score') then
        begin
          LAnswer.Kind := TSOKind.Score;
          LAnswer.Score := LAns.GetValue<Double>('score', 0);
          LAnswer.Confidence := LAns.GetValue<Double>('confidence', 0);
          LValue := LAns.GetValue('probabilities');
          if LValue is TJSONObject then
            ReadProbabilities(LAnswer, TJSONObject(LValue));
        end
        else if SameText(LType, 'noul') then
        begin
          LAnswer.Kind := TSOKind.Noul;
          LAnswer.Noul := LAns.GetValue<Double>('noul', 0);
        end
        else
          raise ESystemOneError.CreateFmt('Answer "%s": unknown type "%s"',
            [LPair.JsonString.Value, LType]);
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    LResp.Free;
  end;
end;

{ TSystemOneLLMAdapter }

constructor TSystemOneLLMAdapter.Create(const ABaseURL, AAPIKey, AModel: string);
begin
  inherited Create;
  FBaseURL := ABaseURL.TrimRight(['/']);
  FAPIKey := AAPIKey;
  FModel := AModel;
  FTimeoutMs := 120000;
  FStructuredOutputs := True;
end;

// The JSON Schema of what the model must answer: for every question an object
// with the probabilities per label (choice, score) or one number (noul).
function TSystemOneLLMAdapter.BuildSchema(const AQuestions: array of TSOQuestion): TJSONObject;
var
  LProps, LAnswerProps, LQProps, LProbProps, LNum: TJSONObject;
  LRequired, LProbRequired, LQRequired: TJSONArray;
  LQ: TSOQuestion;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  LProps := TJSONObject.Create;
  Result.AddPair('properties', LProps);
  LAnswerProps := TJSONObject.Create;
  LProps.AddPair('answers', TJSONObject.Create
    .AddPair('type', 'object')
    .AddPair('properties', LAnswerProps));
  LRequired := TJSONArray.Create;
  for LQ in AQuestions do
  begin
    LQProps := TJSONObject.Create;
    LQRequired := TJSONArray.Create;
    if LQ.Kind = TSOKind.Noul then
    begin
      LNum := TJSONObject.Create.AddPair('type', 'number');
      LQProps.AddPair('noul', LNum);
      LQRequired.Add('noul');
    end
    else
    begin
      LProbProps := TJSONObject.Create;
      LProbRequired := TJSONArray.Create;
      for I := 0 to High(LQ.Labels) do
      begin
        LProbProps.AddPair(LQ.Labels[I], TJSONObject.Create.AddPair('type', 'number'));
        LProbRequired.Add(LQ.Labels[I]);
      end;
      LQProps.AddPair('probabilities', TJSONObject.Create
        .AddPair('type', 'object')
        .AddPair('properties', LProbProps)
        .AddPair('required', LProbRequired)
        .AddPair('additionalProperties', TJSONBool.Create(False)));
      LQRequired.Add('probabilities');
    end;
    LAnswerProps.AddPair(LQ.ID, TJSONObject.Create
      .AddPair('type', 'object')
      .AddPair('properties', LQProps)
      .AddPair('required', LQRequired)
      .AddPair('additionalProperties', TJSONBool.Create(False)));
    LRequired.Add(LQ.ID);
  end;
  TJSONObject(LProps.GetValue('answers')).AddPair('required', LRequired);
  TJSONObject(LProps.GetValue('answers')).AddPair('additionalProperties', TJSONBool.Create(False));
  Result.AddPair('required', TJSONArray.Create.Add('answers'));
  Result.AddPair('additionalProperties', TJSONBool.Create(False));
end;

function TSystemOneLLMAdapter.BuildPrompt(const AState: string;
  const AQuestions: array of TSOQuestion): string;
var
  LSB: TStringBuilder;
  LQ: TSOQuestion;
  I: Integer;
begin
  LSB := TStringBuilder.Create;
  try
    LSB.AppendLine('You are a decision function. Read the STATE and answer every QUESTION on its own, ' +
      'as if the others did not exist. Answer only with the JSON asked for, no text.');
    LSB.AppendLine('For a choice or a score give the probability of EVERY option, between 0 and 1, ' +
      'summing to 1: spread them when the state is ambiguous. For a "noul" give one number between ' +
      '0 (certainly false) and 1 (certainly true).');
    LSB.AppendLine;
    LSB.AppendLine('STATE:').AppendLine(AState).AppendLine;
    LSB.AppendLine('QUESTIONS (id, type, instructions, options):');
    for LQ in AQuestions do
    begin
      LSB.AppendFormat('- id "%s", type %s: %s', [LQ.ID, KindName(LQ.Kind), LQ.Instructions]).AppendLine;
      for I := 0 to High(LQ.Labels) do
        LSB.AppendFormat('    option "%s": %s', [LQ.Labels[I], LQ.Descriptions[I]]).AppendLine;
    end;
    LSB.AppendLine;
    LSB.AppendLine('Answer as {"answers": {"<id>": {"probabilities": {"<option>": p, ...}}}} for choice ' +
      'and score, and {"answers": {"<id>": {"noul": p}}} for noul.');
    Result := LSB.ToString;
  finally
    LSB.Free;
  end;
end;

function TSystemOneLLMAdapter.Ask(const AState: string;
  const AQuestions: array of TSOQuestion): TSOResponse;
var
  LBody, LMsg, LResp, LAnswers, LAns, LProbs, LUsage, LFormat, LJS: TJSONObject;
  LMessages: TJSONArray;
  LContent: string;
  LRoot: TJSONValue;
  LQ: TSOQuestion;
  LAnswer: TSOAnswer;
  LSum, LBest, LP: Double;
  LBestLabel: string;
  K: string;
  LChoices: TJSONArray;
begin
  if Length(AQuestions) = 0 then
    raise ESystemOneError.Create('No question');
  ValidateQuestions(AQuestions);

  LBody := TJSONObject.Create;
  try
    LBody.AddPair('model', FModel);
    LBody.AddPair('temperature', TJSONNumber.Create(0));
    LMessages := TJSONArray.Create;
    LMsg := TJSONObject.Create;
    LMsg.AddPair('role', 'user');
    LMsg.AddPair('content', BuildPrompt(AState, AQuestions));
    LMessages.AddElement(LMsg);
    LBody.AddPair('messages', LMessages);
    if FStructuredOutputs then
    begin
      LFormat := TJSONObject.Create;
      LFormat.AddPair('type', 'json_schema');
      LJS := TJSONObject.Create;
      LJS.AddPair('name', 'system_one_answers');
      LJS.AddPair('strict', TJSONBool.Create(True));
      LJS.AddPair('schema', BuildSchema(AQuestions));
      LFormat.AddPair('json_schema', LJS);
      LBody.AddPair('response_format', LFormat);
    end;
    LResp := PostJSON(FBaseURL + '/chat/completions', FAPIKey, LBody, FTimeoutMs);
  finally
    LBody.Free;
  end;

  try
    LChoices := LResp.GetValue('choices') as TJSONArray;
    if (LChoices = nil) or (LChoices.Count = 0) then
      raise ESystemOneError.Create('The model returned no choices');
    LContent := ((LChoices.Items[0] as TJSONObject).GetValue('message') as TJSONObject)
      .GetValue<string>('content', '');
    // Some servers wrap the JSON in a code fence even when told not to.
    LContent := LContent.Trim;
    if LContent.StartsWith('```') then
    begin
      LContent := Copy(LContent, Pos(#10, LContent) + 1, MaxInt);
      LContent := LContent.Substring(0, LContent.LastIndexOf('```')).Trim;
    end;
    LRoot := TJSONObject.ParseJSONValue(LContent);
    try
      if not (LRoot is TJSONObject) then
        raise ESystemOneError.Create('The model did not return a JSON object: ' + Copy(LContent, 1, 200));
      LAnswers := TJSONObject(LRoot).GetValue('answers') as TJSONObject;
      if LAnswers = nil then
        raise ESystemOneError.Create('The model answer has no "answers"');

      Result := TSOResponse.Create;
      try
        Result.Model := FModel;
        LUsage := LResp.GetValue('usage') as TJSONObject;
        if LUsage <> nil then
        begin
          Result.InputTokens := LUsage.GetValue<Integer>('prompt_tokens', 0);
          Result.OutputTokens := LUsage.GetValue<Integer>('completion_tokens', 0);
        end;
        for LQ in AQuestions do
        begin
          LAns := LAnswers.GetValue(LQ.ID) as TJSONObject;
          if LAns = nil then
            raise ESystemOneError.CreateFmt('The model did not answer question "%s"', [LQ.ID]);
          LAnswer := TSOAnswer.Create;
          Result.Answers.Add(LQ.ID, LAnswer);
          LAnswer.Kind := LQ.Kind;
          if LQ.Kind = TSOKind.Noul then
          begin
            LAnswer.Noul := Min(1, Max(0, LAns.GetValue<Double>('noul', 0)));
            Continue;
          end;
          // Probabilities: keep only the known options, rescale to sum 1.
          LProbs := LAns.GetValue('probabilities') as TJSONObject;
          if LProbs = nil then
            raise ESystemOneError.CreateFmt('Question "%s": no probabilities', [LQ.ID]);
          LSum := 0;
          for K in LQ.Labels do
          begin
            LP := Max(0, LProbs.GetValue<Double>(K, 0));
            LAnswer.Probabilities.AddOrSetValue(K, LP);
            LSum := LSum + LP;
          end;
          if LSum <= 0 then
            raise ESystemOneError.CreateFmt('Question "%s": all probabilities are zero', [LQ.ID]);
          LBest := -1;
          for K in LQ.Labels do   // declaration order breaks a tie
          begin
            LP := LAnswer.Probabilities[K] / LSum;
            LAnswer.Probabilities[K] := LP;
            if LP > LBest then
            begin
              LBest := LP;
              LBestLabel := K;
            end;
          end;
          // Not calibrated: the highest probability the model stated.
          LAnswer.Confidence := LBest;
          if LQ.Kind = TSOKind.Choice then
            LAnswer.Choice := LBestLabel
          else
            LAnswer.Score := StrToInt(LBestLabel);   // the adapter has only the probabilities: the most probable level
        end;
      except
        Result.Free;
        raise;
      end;
    finally
      LRoot.Free;
    end;
  finally
    LResp.Free;
  end;
end;

end.
