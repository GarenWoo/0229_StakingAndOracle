export const formatBalance = (rawBalance: string) => {
  const balance = (parseInt(rawBalance) / 1000000000000000000).toFixed(4)
  return balance
}

export const formatChainInHexAsNum = (chainIdHex: string) => {
  const chainIdNum = parseInt(chainIdHex)
  return chainIdNum
}

export const formatChainInDecimalAsString = (chainIdHex: string) => {
  const chainIdNum = parseInt(chainIdHex).toString();
  return chainIdNum
}