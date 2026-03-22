import os

import stripe

stripe.api_key = os.environ["STRIPE_SECRET_KEY"]


def create_checkout(price_id: str, success_url: str, cancel_url: str):
    return stripe.checkout.Session.create(
        payment_method_types=["card"],
        mode="subscription",
        line_items=[{"price": price_id, "quantity": 1}],
        success_url=success_url,
        cancel_url=cancel_url,
    )
