export class ContractMappingError extends Error {
  constructor(readonly contract: string) {
    super(`The ${contract} response could not be shown safely.`);
    this.name = "ContractMappingError";
  }
}
