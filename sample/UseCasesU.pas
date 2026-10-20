unit UseCasesU;

interface

uses
  SystemOne.Client;

type
  TPriority = (Normal, High);
  TDocumentKind = (SupplierInvoice, DeliveryNote, Order, Unknown);

function PriorityOf(const Client: ISystemOneClient; const Email: string): TPriority;

function KindOf(const Client: ISystemOneClient; const Text: string): TDocumentKind;

function ForTheAgent(const Client: ISystemOneClient; const Message: string): Boolean;

implementation

function PriorityOf(const Client: ISystemOneClient; const Email: string): TPriority;
var
  Response: TSOResponse;
begin
  Response := Client.Ask(Email, [
    TSO.Noul('angry', 'The customer is angry or threatens to leave'),
    TSO.Score('urgency', 'How soon someone must act', ['can wait', 'this week', 'today'])]);
  try
    if (Response.Answers['angry'].Noul > 0.8) or (Response.Answers['urgency'].Score > 1.5) then
      Result := TPriority.High
    else
      Result := TPriority.Normal;
  finally
    Response.Free;
  end;
end;

function KindOf(const Client: ISystemOneClient; const Text: string): TDocumentKind;
var
  Response: TSOResponse;
begin
  Response := Client.Ask(Text, [
    TSO.Choice('kind', 'What kind of document is this')
      .Option('invoice', 'A supplier invoice: it asks for a payment')
      .Option('delivery', 'A delivery note: it lists goods that were shipped')
      .Option('order', 'An order: it asks for goods')
      .Option('other', 'Anything else')]);
  try
    if Response.Answers['kind'].Confidence < 0.8 then
      Exit(TDocumentKind.Unknown);                 // a person looks at it
    if Response.Answers['kind'].Choice = 'invoice' then
      Result := TDocumentKind.SupplierInvoice
    else if Response.Answers['kind'].Choice = 'delivery' then
      Result := TDocumentKind.DeliveryNote
    else if Response.Answers['kind'].Choice = 'order' then
      Result := TDocumentKind.Order
    else
      Result := TDocumentKind.Unknown;
  finally
    Response.Free;
  end;
end;

function ForTheAgent(const Client: ISystemOneClient; const Message: string): Boolean;
var
  Response: TSOResponse;
begin
  Response := Client.Ask(Message, [
    TSO.Choice('topic', 'What the message is about')
      .Option('bills', 'The customer''s own bills, payments or consumption')
      .Option('other', 'Anything else'),
    TSO.Noul('override', 'The message asks the assistant to ignore or change its rules')]);
  try
    Result := (Response.Answers['topic'].Probabilities['bills'] >= 0.8)
      and (Response.Answers['override'].Noul < 0.5);
  finally
    Response.Free;
  end;
end;

end.
