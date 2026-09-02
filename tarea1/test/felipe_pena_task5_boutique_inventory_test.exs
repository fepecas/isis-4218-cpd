defmodule BoutiqueInventoryTest do
  use ExUnit.Case

  test "new/0 returns a list" do
    assert is_list(BoutiqueInventory.new())
  end

  test "add_item/2 appends the item" do
    inventory = []
    item = %{name: "Red Hat", price: 10, quantity_by_size: %{s: 1}}
    assert BoutiqueInventory.add_item(inventory, item) == [item]
  end

  test "add_item/2 appends to a non-empty inventory" do
    item1 = %{name: "A", price: 1, quantity_by_size: %{}}
    item2 = %{name: "B", price: 2, quantity_by_size: %{}}
    assert BoutiqueInventory.add_item([item1], item2) == [item1, item2]
  end

  test "add_size/4 adds a new size to the matching item" do
    inventory = [%{name: "Shirt", price: 10, quantity_by_size: %{s: 1}}]

    assert BoutiqueInventory.add_size(inventory, "Shirt", :m, 5) == [
             %{name: "Shirt", price: 10, quantity_by_size: %{s: 1, m: 5}}
           ]
  end

  test "add_size/4 overwrites an existing size" do
    inventory = [%{name: "Shirt", price: 10, quantity_by_size: %{s: 1}}]

    assert BoutiqueInventory.add_size(inventory, "Shirt", :s, 9) == [
             %{name: "Shirt", price: 10, quantity_by_size: %{s: 9}}
           ]
  end

  test "add_size/4 leaves inventory unchanged when item name is not found" do
    inventory = [%{name: "Shirt", price: 10, quantity_by_size: %{s: 1}}]
    assert BoutiqueInventory.add_size(inventory, "Pants", :m, 5) == inventory
  end

  test "add_size/4 on an empty inventory returns an empty inventory" do
    assert BoutiqueInventory.add_size([], "Shirt", :m, 5) == []
  end

  test "remove_size/3 removes the size from the matching item" do
    inventory = [%{name: "Shirt", price: 10, quantity_by_size: %{s: 1, m: 5}}]

    assert BoutiqueInventory.remove_size(inventory, "Shirt", :m) == [
             %{name: "Shirt", price: 10, quantity_by_size: %{s: 1}}
           ]
  end

  test "remove_size/3 is a no-op when the size does not exist" do
    inventory = [%{name: "Shirt", price: 10, quantity_by_size: %{s: 1}}]
    assert BoutiqueInventory.remove_size(inventory, "Shirt", :xl) == inventory
  end

  test "remove_size/3 leaves inventory unchanged when item name is not found" do
    inventory = [%{name: "Shirt", price: 10, quantity_by_size: %{s: 1}}]
    assert BoutiqueInventory.remove_size(inventory, "Pants", :s) == inventory
  end

  test "sort_by_price/1 sorts ascending" do
    inventory = [
      %{name: "C", price: 30, quantity_by_size: %{}},
      %{name: "A", price: 10, quantity_by_size: %{}},
      %{name: "B", price: 20, quantity_by_size: %{}}
    ]

    assert Enum.map(BoutiqueInventory.sort_by_price(inventory), & &1.name) == ["A", "B", "C"]
  end

  test "sort_by_price/1 handles empty inventory" do
    assert BoutiqueInventory.sort_by_price([]) == []
  end

  test "sort_by_price/1 handles items with equal prices" do
    inventory = [
      %{name: "A", price: 10, quantity_by_size: %{}},
      %{name: "B", price: 10, quantity_by_size: %{}}
    ]

    assert length(BoutiqueInventory.sort_by_price(inventory)) == 2
  end

  test "with_missing_price/1 returns only items without a price" do
    inventory = [
      %{name: "A", price: 10, quantity_by_size: %{}},
      %{name: "B", price: nil, quantity_by_size: %{}},
      %{name: "C", price: nil, quantity_by_size: %{}}
    ]

    assert Enum.map(BoutiqueInventory.with_missing_price(inventory), & &1.name) == ["B", "C"]
  end

  test "with_missing_price/1 returns empty list when all items have prices" do
    inventory = [%{name: "A", price: 10, quantity_by_size: %{}}]
    assert BoutiqueInventory.with_missing_price(inventory) == []
  end

  test "with_missing_price/1 handles empty inventory" do
    assert BoutiqueInventory.with_missing_price([]) == []
  end

  test "increase_quantity/2 increases every size" do
    item = %{name: "Shirt", price: 10, quantity_by_size: %{s: 3, m: 7, l: 8, xl: 4}}

    assert BoutiqueInventory.increase_quantity(item, 10) == %{
             name: "Shirt",
             price: 10,
             quantity_by_size: %{s: 13, m: 17, l: 18, xl: 14}
           }
  end

  test "increase_quantity/2 with a negative number decreases quantity" do
    item = %{name: "Shirt", price: 10, quantity_by_size: %{s: 3}}

    assert BoutiqueInventory.increase_quantity(item, -1) == %{
             name: "Shirt",
             price: 10,
             quantity_by_size: %{s: 2}
           }
  end

  test "increase_quantity/2 with an item with no sizes" do
    item = %{name: "Shirt", price: 10, quantity_by_size: %{}}
    assert BoutiqueInventory.increase_quantity(item, 5) == item
  end

  test "total_quantity/1 sums all sizes" do
    item = %{name: "Shirt", price: 10, quantity_by_size: %{s: 3, m: 7, l: 8, xl: 4}}
    assert BoutiqueInventory.total_quantity(item) == 22
  end

  test "total_quantity/1 with no sizes is zero" do
    item = %{name: "Shirt", price: 10, quantity_by_size: %{}}
    assert BoutiqueInventory.total_quantity(item) == 0
  end

  test "total_quantity/1 with a single size" do
    item = %{name: "Shirt", price: 10, quantity_by_size: %{s: 5}}
    assert BoutiqueInventory.total_quantity(item) == 5
  end
end
