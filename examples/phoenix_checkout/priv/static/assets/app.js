(() => {
  const page = document.body;
  const checkoutUrl = page.dataset.checkoutUrl;

  if (!checkoutUrl) return;

  const button = document.querySelector("#open-checkout");
  const status = document.querySelector("#checkout-status");
  const checkout = window.DodoPaymentsCheckout?.DodoPayments;

  if (!checkout) {
    status.textContent = "The checkout library did not load. Use the full-page checkout link.";
    button.disabled = true;
    return;
  }

  checkout.Initialize({
    mode: page.dataset.dodoMode,
    displayType: "overlay",
    onEvent: (event) => {
      switch (event.event_type) {
        case "checkout.opened":
        case "checkout.form_ready":
          status.textContent = "Checkout opened securely.";
          button.disabled = false;
          break;
        case "checkout.closed":
          status.textContent = "Checkout closed. You can reopen it when ready.";
          button.disabled = false;
          break;
        case "checkout.error":
          status.textContent = "Checkout could not open. Try the full-page link.";
          button.disabled = false;
          break;
      }
    }
  });

  const openCheckout = async () => {
    button.disabled = true;
    status.textContent = "Opening the payment overlay…";

    try {
      await checkout.Checkout.open({checkoutUrl});
    } catch (_error) {
      status.textContent = "Checkout could not open. Try the full-page link.";
      button.disabled = false;
    }
  };

  button.addEventListener("click", openCheckout);

  if (page.dataset.autoOpen === "true") openCheckout();
})();
