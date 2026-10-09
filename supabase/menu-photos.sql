-- Hanging Garden Café · menu photos: a bright daylight picture for every drink and every food item
-- Run ONCE in Supabase: SQL Editor -> New query -> paste -> Run. Safe to run again.
--   44 photos in one look (light wood, soft daylight, misty garden) so they read well on the TV behind
--   the window and on the website. Extras & Combos have no photo on purpose.
--   Any picture can still be changed one by one in the Menu Manager.
--   The previous pictures (Menti Verde had a logo instead of the drink) are at the bottom, to undo.
update public.menu_items m
   set photo_url = 'https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/' || p.file
  from (values
    -- Coffee
    ('cbaa2cca-9b2d-4a14-8580-e1d2f3ac01d2', '79157cea-21d9-4095-8e1a-b9a245c2b497.jpg'),  -- Espresso
    ('410256ce-df43-4443-88f2-b3da9ab491f7', '7a0fc550-f9e0-4cd3-b3ff-c436116c05ed.jpg'),  -- Americano
    ('edd04f12-f276-4991-9922-e877ba5d3ae1', 'efe2efae-2878-4962-bdcd-f4c5c1a89d03.jpg'),  -- Macchiato
    ('4617ff31-05c3-40a9-a45f-38e32b57e843', '99f8e8d4-585f-4240-86bb-e5873eb9e247.jpg'),  -- Cappuccino Small
    ('6d5f4c92-27b9-47db-8801-64dde03b0439', '3ba4e74d-5b24-4e1a-9f2b-4eb4abd0ecdd.jpg'),  -- Latte
    ('5c82a7b4-8aa5-4951-954d-7a068e63903a', 'd3064102-a2ee-4893-b1c0-8606b2f06654.jpg'),  -- Flat White
    ('e8e1cbb6-27d3-45a2-b450-9cbd1966bb48', 'b98706cd-bca0-480e-ba99-523603d94b34.jpg'),  -- Mocha
    ('1456f933-86e2-4c08-a8dc-2302adebce36', '00e595f8-156c-4d66-b6ce-2318836bbba0.jpg'),  -- Café con Leche
    ('1dd19f21-5328-4349-b8cb-16a7527ccf4a', '390a749c-0213-4ac1-9762-fb28fb685e0d.jpg'),  -- Canela Cloud
    ('3cdbec50-b562-4609-8f11-fc448273a14b', 'b2ec005b-7032-4321-b9d3-7392b83cef5a.jpg'),  -- Iced Americano
    ('3b13280d-0749-467a-bdc2-ced0ace07706', '530fbcc0-b7a1-46a8-ad6d-badac5ace509.jpg'),  -- Iced Latte
    ('1fb061ff-1e48-4c28-b911-5fb1e079aa6f', '2aaefcb4-dadb-4fc5-ad47-349f3038cec6.jpg'),  -- Iced Mocha
    ('e1f1df86-da9e-4ae7-8751-dc46452614fe', 'eb2e0880-887a-4f2b-a1af-333689a5b9a0.jpg'),  -- Cappuchino Large
    -- Other Drinks
    ('de53550c-7e8f-46c3-b32d-3ebd97736010', 'bc49e377-796a-4862-b7f5-56dc8ca64cc2.jpg'),  -- Costa Rican Hot Chocolate
    ('5d498c9e-231b-4f16-9d25-f064f5acaef5', 'a704aad7-59e6-43bb-a856-3441f3013ec5.jpg'),  -- Tea
    ('b4822dce-c2a9-4979-8a79-de2a0220a481', '098c9ae3-ef1e-491f-93f8-e4ca04828a56.jpg'),  -- Sweet Cane Drink
    ('0ca57acd-6e8b-48b5-8f13-ff0e5b949f56', 'b108d3d3-81a3-4f43-a014-f378ef917d69.jpg'),  -- Menti Verde
    -- Smoothies
    ('ce908b50-72ce-4ffa-b54b-c295f12b8d4b', 'd293a2cb-3232-49c1-aac6-0ee2b0631b41.jpg'),  -- Golden Passion Bloom
    ('1ee93c0c-cff5-40fd-8dad-a254705acab2', '076a95ef-25c5-4b1c-b8a9-7ef55257a5a1.jpg'),  -- White Plumeria Cream
    ('27db540d-daaf-4655-a24f-d7efe4dcf265', 'd93f5592-9d5c-4aac-8d3a-21091d8088c6.jpg'),  -- Sunflower Citrus Bloom
    ('cc802884-f5a7-484f-b9dc-dd8c083a7d0c', '88210740-1fb2-4bea-8ba5-fedea5b49540.jpg'),  -- Green Jasmine Mint
    ('367db827-c93e-4db4-85a0-62c0c90d7121', 'cf02cb04-ab41-4f5b-929d-5319a4acb7ab.jpg'),  -- Coral Rose Splash
    ('97327f1d-350f-4895-bc0d-69c13e18ec2a', 'd33f8573-ae47-4563-b507-fe114e7e4d1b.jpg'),  -- Pink Dahlia Delight
    ('e70e8c46-6c5d-48b0-9a71-72f076b7f004', 'cd67944a-7ad3-4046-9297-b50e27e7db06.jpg'),  -- Emerald Orchid
    ('c287a1a3-b6f2-4d28-886d-d106e256cc41', 'b0665dbc-95c3-4832-bfa5-33dea77e0b11.jpg'),  -- Lemon Rose Blossom
    ('ffd68945-a96f-483c-adfc-f9879c2443de', 'c52b11ae-7c2d-485b-bd44-fdbac736cc1b.jpg'),  -- Fresh Water Lily
    ('f421a1a6-ccf3-40ad-a600-d35629f6d124', '5d209cc1-02da-4267-9ccb-5e2759c56047.jpg'),  -- Golden Magnolia
    -- Sandwiches
    ('35c20b9e-b5e4-446a-89e1-7714fad2568a', 'cb13d227-42f3-4a0d-ab97-3412578a936c.jpg'),  -- Ham & Cheese
    ('be7ab24f-2921-41ce-ad1c-f4f31faf586d', '08a7500a-a3a1-4666-8b72-5404f65f8d50.jpg'),  -- Mano de Piedra
    ('b6bac9e1-fe5b-4870-a28f-df4a80f1a179', 'd6248f85-b888-4267-8162-6e52e67c0403.jpg'),  -- Chicken Pesto
    ('75a63bac-b022-4c00-a4cd-ac5f683b8549', '0f2a8ec0-7f6a-476f-97cf-a1456d39f13a.jpg'),  -- Monteverde
    -- Savory
    ('5f762132-c69c-4143-92ee-4738d036e2b0', '3492513f-d669-480f-9b96-3f9b56ca0bb4.jpg'),  -- Ham & Cheese Croissant
    -- Pastries & Cake
    ('c1025cef-d15d-4dfd-ae80-00062f5bfbd0', 'f9980afe-cd96-49e3-a51f-fc1e3ba5a8b3.jpg'),  -- Butter Croissant
    ('0b6cd119-e9a1-4e33-8cbd-99d59e06401d', 'b35c3b5e-490b-47d1-97bb-1f9ad00c9475.jpg'),  -- Chocolate Croissant
    ('52537d85-f2b3-4039-b9cd-28a3483a3b3c', 'a3ac44bf-ecac-4c34-a0a1-d58622d47797.jpg'),  -- Banana Bread
    ('0f2fb863-cbc8-422a-911b-34a57a55137c', 'cb438158-145d-4878-b8d2-2c409548693f.jpg'),  -- Carrot Cake
    ('5ed08677-8c7c-4c04-bbb5-fbabc1472725', '04e87afc-b368-4fe4-9fcc-245037d680c6.jpg'),  -- Rollo De Canela
    ('c8db8cfa-7335-4229-90c8-f1c2dd3aa0ca', '301f784d-bcfc-4365-a0b5-1f07609e125b.jpg'),  -- Triple Chocolate Croissant
    ('72c605f7-b471-4e15-9ccb-e9d453b7c976', 'd9dc47c8-bdfe-4501-bf48-bb9fc3a810cf.jpg'),  -- Bun N Roll Breakfast
    ('92f5d8be-9993-4247-a443-3cb312aa68c9', '3e7dd60e-64a5-41d9-9eb8-48c3835d46c8.jpg'),  -- Flauta de Chocolate
    -- Costa Rican Favorites
    ('20ed7833-c70d-451a-8e99-7ae912d89f92', '2626c44c-f7f9-4aa1-873c-7a43e11e780f.jpg'),  -- Tres Leches
    ('9eec0ebf-ed81-4d40-b4ab-9b313c8af64b', '84c9a0f5-c518-44ee-a7f8-7b02af4ce261.jpg'),  -- Tamal Asado
    -- Adventure Box
    ('b86aa2cc-b6d6-4671-8254-d0632475336f', '7ca40d6d-01c5-42bc-8cf3-4aad906be597.jpg'),  -- Adventure Box · Ham & Cheese or Monteverde
    ('33d67713-9172-4992-9789-2f04d1b36a6b', '49f96966-a1d6-479f-9ce6-73235d6ef4da.jpg')  -- Adventure Box · Mano de Piedra or Chicken Pesto
  ) as p(id, file)
 where m.id = p.id::uuid;

-- Check: on_menu and with_photo should match in every row
select c.name as category,
       count(*) filter (where i.available) as on_menu,
       count(*) filter (where i.available and i.photo_url is not null) as with_photo
  from public.menu_items i join public.menu_categories c on c.id = i.category_id
 where c.name <> 'Extras & Combos'
 group by c.name, c.sort order by c.sort;

-- To go back to a previous picture, run its line without the leading -- (the other items had no picture):
-- update public.menu_items set photo_url = 'https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/574b4dfb-ca7c-4fee-b069-ccce677c3d97.jpg' where id = '4617ff31-05c3-40a9-a45f-38e32b57e843';  -- Cappuccino Small
-- update public.menu_items set photo_url = 'https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/e9863237-62a2-49a4-a63b-367c4a8f5efa.jpg' where id = '1dd19f21-5328-4349-b8cb-16a7527ccf4a';  -- Canela Cloud
-- update public.menu_items set photo_url = 'https://nbvczarfweanoxvdqplk.supabase.co/storage/v1/object/public/menu-photos/0ca57acd-6e8b-48b5-8f13-ff0e5b949f56-1788558445485.png' where id = '0ca57acd-6e8b-48b5-8f13-ff0e5b949f56';  -- Menti Verde
-- update public.menu_items set photo_url = 'https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/ae462fb2-15f7-4c39-9063-4c3fd2addd33.jpg' where id = 'ce908b50-72ce-4ffa-b54b-c295f12b8d4b';  -- Golden Passion Bloom
-- update public.menu_items set photo_url = 'https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/4f9edb15-11a3-454f-9d86-c1fc0ed481a4.jpg' where id = 'be7ab24f-2921-41ce-ad1c-f4f31faf586d';  -- Mano de Piedra
-- update public.menu_items set photo_url = 'https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/df5479cc-e700-4161-9895-dfa51d99cef1.jpg' where id = '0b6cd119-e9a1-4e33-8cbd-99d59e06401d';  -- Chocolate Croissant
-- update public.menu_items set photo_url = 'https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/e1bda9ca-d285-4bbf-ad31-e82672a9e958.jpg' where id = '0f2fb863-cbc8-422a-911b-34a57a55137c';  -- Carrot Cake
-- update public.menu_items set photo_url = 'https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/e2cbc800-55bc-4466-800a-012db2290e14.jpg' where id = '20ed7833-c70d-451a-8e99-7ae912d89f92';  -- Tres Leches
