/*************************************************************************
 *
 * REALM CONFIDENTIAL
 * __________________
 *
 *  [2011] - [2012] Realm Inc
 *  All Rights Reserved.
 *
 * NOTICE:  All information contained herein is, and remains
 * the property of Realm Incorporated and its suppliers,
 * if any.  The intellectual and technical concepts contained
 * herein are proprietary to Realm Incorporated
 * and its suppliers and may be covered by U.S. and Foreign Patents,
 * patents in process, and are protected by trade secret or copyright law.
 * Dissemination of this information or reproduction of this material
 * is strictly forbidden unless prior written permission is obtained
 * from Realm Incorporated.
 *
 **************************************************************************/
#ifndef REALM_ARRAY_BLOB_HPP
#define REALM_ARRAY_BLOB_HPP

#include <realm/array.hpp>

namespace realm {


class ArrayBlob: public Array {
public:
    explicit ArrayBlob(Allocator&) REALM_NOEXCEPT;
    ~ArrayBlob() REALM_NOEXCEPT override {}

    const char* get(std::size_t index) const REALM_NOEXCEPT;
    bool is_null(std::size_t index) const REALM_NOEXCEPT;
    void add(const char* data, std::size_t size, bool add_zero_term = false);
    void insert(std::size_t pos, const char* data, std::size_t size, bool add_zero_term = false);
    void replace(std::size_t begin, std::size_t end, const char* data, std::size_t size,
                 bool add_zero_term = false);
    void erase(std::size_t begin, std::size_t end);

    /// Get the specified element without the cost of constructing an
    /// array instance. If an array instance is already available, or
    /// you need to get multiple values, then this method will be
    /// slower.
    static const char* get(const char* header, std::size_t index) REALM_NOEXCEPT;

    /// Create a new empty blob (binary) array and attach this
    /// accessor to it. This does not modify the parent reference
    /// information of this accessor.
    ///
    /// Note that the caller assumes ownership of the allocated
    /// underlying node. It is not owned by the accessor.
    void create();

    /// Construct a blob of the specified size and return just the
    /// reference to the underlying memory. All bytes will be
    /// initialized to zero.
    static MemRef create_array(std::size_t size, Allocator&);

#ifdef REALM_DEBUG
    void Verify() const;
    void to_dot(std::ostream&, StringData title = StringData()) const;
#endif

private:
    std::size_t CalcByteLen(std::size_t count, std::size_t width) const override;
    std::size_t CalcItemCount(std::size_t bytes,
                              std::size_t width) const REALM_NOEXCEPT override;
    WidthType GetWidthType() const override { return wtype_Ignore; }
};




// Implementation:

// Creates new array (but invalid, call init_from_ref() to init)
inline ArrayBlob::ArrayBlob(Allocator& alloc) REALM_NOEXCEPT:
    Array(alloc)
{
}

inline bool ArrayBlob::is_null(std::size_t index) const REALM_NOEXCEPT
{
    return (get(index) == nullptr);
}

inline const char* ArrayBlob::get(std::size_t index) const REALM_NOEXCEPT
{
    return m_data + index;
}

inline void ArrayBlob::add(const char* data, std::size_t size, bool add_zero_term)
{
    replace(m_size, m_size, data, size, add_zero_term);
}

inline void ArrayBlob::insert(std::size_t pos, const char* data, std::size_t size,
                              bool add_zero_term)
{
    replace(pos, pos, data, size, add_zero_term);
}

inline void ArrayBlob::erase(std::size_t begin, std::size_t end)
{
    const char* data = nullptr;
    std::size_t size = 0;
    replace(begin, end, data, size);
}

inline const char* ArrayBlob::get(const char* header, std::size_t pos) REALM_NOEXCEPT
{
    const char* data = get_data_from_header(header);
    return data + pos;
}

inline void ArrayBlob::create()
{
    std::size_t size = 0;
    MemRef mem = create_array(size, get_alloc()); // Throws
    init_from_mem(mem);
}

inline MemRef ArrayBlob::create_array(std::size_t size, Allocator& alloc)
{
    bool context_flag = false;
    int_fast64_t value = 0;
    return Array::create(type_Normal, context_flag, wtype_Ignore, size, value, alloc); // Throws
}

inline std::size_t ArrayBlob::CalcByteLen(std::size_t count, std::size_t) const
{
    return header_size + count;
}

inline std::size_t ArrayBlob::CalcItemCount(std::size_t bytes, std::size_t) const REALM_NOEXCEPT
{
    return bytes - header_size;
}


} // namespace realm

#endif // REALM_ARRAY_BLOB_HPP
