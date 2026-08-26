export type GatewayErrorKind =
  | "configuration"
  | "network"
  | "timeout"
  | "canceled"
  | "authentication"
  | "authorization"
  | "http"
  | "invalidResponse";

export class GatewayError extends Error {
  constructor(
    readonly kind: GatewayErrorKind,
    message: string,
    readonly options: { status?: number; detail?: string } = {}
  ) {
    super(message);
    this.name = "GatewayError";
  }

  get status(): number | undefined {
    return this.options.status;
  }
}

export function gatewayErrorMessage(error: unknown): string {
  if (!(error instanceof GatewayError)) return "The eFlow service could not be reached. Try again.";

  switch (error.kind) {
    case "configuration":
      return "The eFlow service endpoint is unavailable. Try again shortly.";
    case "network":
      return "Check your internet connection and try again.";
    case "timeout":
      return "The eFlow service took too long to respond. Try again.";
    case "canceled":
      return "The request was canceled.";
    case "authentication":
      return "Your session has expired. Sign in again.";
    case "authorization":
      return "You do not have permission to use this eFlow service.";
    case "invalidResponse":
      return "The eFlow service returned an unexpected response. Try again later.";
    case "http":
      return "The eFlow service is temporarily unavailable. Try again shortly.";
  }
}

