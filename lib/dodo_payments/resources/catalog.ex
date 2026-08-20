defmodule DodoPayments.Addons do
  @moduledoc "Add-on catalogue operations."
  use DodoPayments.Service
  operation(:list, :addons_list)
  operation(:create, :addons_create)
  operation(:retrieve, :addons_retrieve, path: [:id], params: false)
  operation(:update, :addons_update, path: [:id])
  operation(:update_images, :addons_update_images, path: [:id], params: false)
end

defmodule DodoPayments.Brands do
  @moduledoc "Brand and brand-image operations."
  use DodoPayments.Service
  operation(:list, :brands_list)
  operation(:create, :brands_create)
  operation(:retrieve, :brands_retrieve, path: [:id], params: false)
  operation(:update, :brands_update, path: [:id])
  operation(:update_images, :brands_update_images, path: [:id], params: false)
  operation(:archive, :brands_archive, path: [:id])
end

defmodule DodoPayments.CheckoutSessions do
  @moduledoc "Hosted checkout creation, preview and status operations."
  use DodoPayments.Service
  operation(:create, :checkout_sessions_create)
  operation(:retrieve, :checkout_sessions_retrieve, path: [:id], params: false)
  operation(:preview, :checkout_sessions_preview)
end

defmodule DodoPayments.SupportedCountries do
  @moduledoc "Countries supported by Dodo checkout."
  use DodoPayments.Service
  operation(:list, :supported_countries_list, params: false)
end

defmodule DodoPayments.Products do
  @moduledoc "Product lifecycle operations."
  use DodoPayments.Service
  operation(:list, :products_list)
  operation(:create, :products_create)
  operation(:retrieve, :products_retrieve, path: [:id], params: false)
  operation(:update, :products_update, path: [:id])
  operation(:archive, :products_archive, path: [:id], params: false)
  operation(:unarchive, :products_unarchive, path: [:id], params: false)
  operation(:update_files, :products_update_files, path: [:id])
end

defmodule DodoPayments.Products.Images do
  @moduledoc "Product image upload/update operations."
  use DodoPayments.Service
  operation(:update, :product_images_update, path: [:id])
end

defmodule DodoPayments.Products.ShortLinks do
  @moduledoc "Product short-link operations."
  use DodoPayments.Service
  operation(:list, :product_short_links_list)
  operation(:create, :product_short_links_create, path: [:id])
end

defmodule DodoPayments.Products.LocalizedPrices do
  @moduledoc "Localized price operations for a product."
  use DodoPayments.Service
  operation(:list, :localized_prices_list, path: [:product_id], params: false)
  operation(:create, :localized_prices_create, path: [:product_id])
  operation(:retrieve, :localized_prices_retrieve, path: [:product_id, :id], params: false)
  operation(:update, :localized_prices_update, path: [:product_id, :id])
  operation(:archive, :localized_prices_archive, path: [:product_id, :id], params: false)
end

defmodule DodoPayments.ProductCollections do
  @moduledoc "Product collection lifecycle operations."
  use DodoPayments.Service
  operation(:list, :product_collections_list)
  operation(:create, :product_collections_create)
  operation(:retrieve, :product_collections_retrieve, path: [:id], params: false)
  operation(:archive, :product_collections_archive, path: [:id], params: false)
  operation(:update, :product_collections_update, path: [:id])
  operation(:update_images, :product_collections_update_images, path: [:id])
  operation(:unarchive, :product_collections_unarchive, path: [:id], params: false)
end

defmodule DodoPayments.ProductCollections.Groups do
  @moduledoc "Groups within a product collection."
  use DodoPayments.Service
  operation(:create, :collection_groups_create, path: [:id])
  operation(:delete, :collection_groups_delete, path: [:id, :group_id], params: false)
  operation(:update, :collection_groups_update, path: [:id, :group_id])
end

defmodule DodoPayments.ProductCollections.Groups.Items do
  @moduledoc "Items within a product-collection group."
  use DodoPayments.Service
  operation(:create, :collection_group_items_create, path: [:id, :group_id])

  operation(:delete, :collection_group_items_delete,
    path: [:id, :group_id, :item_id],
    params: false
  )

  operation(:update, :collection_group_items_update, path: [:id, :group_id, :item_id])
end

defmodule DodoPayments.Discounts do
  @moduledoc "Discount lifecycle and code lookup operations."
  use DodoPayments.Service
  operation(:list, :discounts_list)
  operation(:create, :discounts_create)
  operation(:retrieve, :discounts_retrieve, path: [:discount_id], params: false)
  operation(:delete, :discounts_delete, path: [:discount_id], params: false)
  operation(:update, :discounts_update, path: [:discount_id])
  operation(:retrieve_by_code, :discounts_retrieve_by_code, path: [:code], params: false)
  operation(:list_customers, :discount_customers_list, path: [:discount_id])
  operation(:attach_customers, :discount_customers_attach, path: [:discount_id])

  operation(:detach_customer, :discount_customers_detach,
    path: [:discount_id, :customer_id],
    params: false
  )
end
