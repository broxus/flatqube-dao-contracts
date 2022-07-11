const waitFinalized = async function(tx_promise) {
    const subscriber = new locklift.provider.ever.Subscriber();
    const {transaction} = await tx_promise;
    await subscriber.trace(transaction).finished();
    await subscriber.unsubscribe();
    return transaction;
}


module.exports = {
    waitFinalized
}
