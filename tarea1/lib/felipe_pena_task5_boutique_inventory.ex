defmodule BoutiqueInventory do
  def new do
    [
      %{name: "Green T-shirt", price: 20, quantity_by_size: %{s: 5, m: 10, l: 5, xl: 2}},
      %{name: "Black Jeans", price: 40, quantity_by_size: %{s: 3, m: 7, l: 8, xl: 4}},
      %{name: "Kids Overalls", price: nil, quantity_by_size: %{s: 5, m: 10, l: 5, xl: 2}}
    ]
  end

  def add_item(inventory, item) do
    inventory ++ [item]
  end

  def add_size(inventory, item_name, size, quantity) do
    Enum.map(inventory, fn
      %{name: ^item_name, quantity_by_size: sizes} = item ->
        %{item | quantity_by_size: Map.put(sizes, size, quantity)}

      item ->
        item
    end)
  end

  def remove_size(inventory, item_name, size) do
    Enum.map(inventory, fn
      %{name: ^item_name, quantity_by_size: sizes} = item ->
        %{item | quantity_by_size: Map.delete(sizes, size)}

      item ->
        item
    end)
  end

  def sort_by_price(inventory) do
    Enum.sort_by(inventory, & &1.price)
  end

  def with_missing_price(inventory) do
    Enum.filter(inventory, &is_nil(&1.price))
  end

  def increase_quantity(item, n) do
    updated_sizes =
      Map.new(item.quantity_by_size, fn {size, quantity} -> {size, quantity + n} end)

    %{item | quantity_by_size: updated_sizes}
  end

  def total_quantity(item) do
    item.quantity_by_size
    |> Map.values()
    |> Enum.sum()
  end
end
